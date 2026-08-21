defmodule EasyBreezy.PresenterViewTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.Deck.Markdown
  alias EasyBreezy.{Deck, PresentationTiming, Slide}

  defmodule LivePreviewView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 0)}

    def render(assigns) do
      ~H"""
      <box class="width-full height-full">
        <box>Live counter</box>
        <box>value: {@count}</box>
      </box>
      """
    end
  end

  defmodule RecordingTerminal do
    def write(%{owner: owner} = term, output) do
      send(owner, {:terminal_write, output})
      {:ok, term}
    end
  end

  test "escape does not close the presenter" do
    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, _focused, false} = Breeze.Test.input(session, "Escape")
    assert Process.alive?(session.pid)
  end

  test "mount restores the presentation timer from start options" do
    started_at_ms = System.monotonic_time(:millisecond) - 125_000

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, started_at_ms: started_at_ms]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.metadata(session).assigns.started_at_ms == started_at_ms
  end

  test "ctrl+r prompts before resetting the timer" do
    sync_name = {:easy_breezy_reset_timer_test, System.unique_integer([:positive])}
    EasyBreezy.PresenterSync.register(sync_name)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, sync_name: sync_name]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_receive {:easy_breezy_presenter_subscribe, _pid}

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, nil, %{"ctrlKey" => true, "key" => "r"})

    assert Breeze.Test.metadata(session).assigns.reset_timer_modal?

    plain = session |> Breeze.Test.render!() |> strip_ansi()
    assert plain =~ "Reset Timer"
    assert plain =~ "Reset elapsed timer to 00:00?"
    refute_receive {:easy_breezy_presenter_command, _pid, :reset_timer}

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Escape")
    refute Breeze.Test.metadata(session).assigns.reset_timer_modal?
    refute session |> Breeze.Test.render!() |> strip_ansi() =~ "Reset Timer"
    refute_receive {:easy_breezy_presenter_command, _pid, :reset_timer}
  end

  test "confirming the reset timer prompt resets the local clock and presentation timer" do
    sync_name = {:easy_breezy_reset_timer_test, System.unique_integer([:positive])}
    EasyBreezy.PresenterSync.register(sync_name)
    metadata_dir = temporary_metadata_dir()
    on_exit(fn -> File.rm_rf(metadata_dir) end)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: text_deck(),
          theme: :nebula,
          sync_name: sync_name,
          metadata_dir: metadata_dir
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_receive {:easy_breezy_presenter_subscribe, _pid}

    old_started_at_ms = System.monotonic_time(:millisecond) - 125_000

    Breeze.Test.info(
      session,
      {:easy_breezy_presentation_state,
       presentation_payload(text_deck(), 0)
       |> Map.put(:elapsed_ms, 125_000)
       |> Map.put(:started_at_ms, old_started_at_ms)}
    )

    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Elapsed 02:05"

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, nil, %{"ctrlKey" => true, "key" => "r"})

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Enter")

    refute Breeze.Test.metadata(session).assigns.reset_timer_modal?
    assert Breeze.Test.metadata(session).assigns.started_at_ms > old_started_at_ms
    assert Breeze.Test.metadata(session).assigns.timing_run.status == :active
    assert File.dir?(Path.join(metadata_dir, "timings"))
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Elapsed 00:00"
    assert_receive {:easy_breezy_presenter_command, _pid, :reset_timer}
  end

  test "slide timing continues independently of a paused presentation timer" do
    metadata_dir = temporary_metadata_dir()
    on_exit(fn -> File.rm_rf(metadata_dir) end)
    deck = preview_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {120, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula, metadata_dir: metadata_dir]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})

    Breeze.Test.event(session, nil, %{"ctrlKey" => true, "key" => "r"})
    Breeze.Test.input(session, "Enter")

    timing_run = Breeze.Test.metadata(session).assigns.timing_run
    assert timing_run.tracked_slide_index == 0

    Breeze.Test.input(session, "p")
    paused_assigns = Breeze.Test.metadata(session).assigns

    assert paused_assigns.timer_paused?
    assert paused_assigns.timing_run.segment_started_at_ms == timing_run.segment_started_at_ms

    Process.sleep(2)

    payload =
      deck
      |> presentation_payload(1)
      |> Map.put(:timer_paused?, true)
      |> Map.put(:elapsed_ms, paused_assigns.paused_elapsed_ms)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})

    run = Breeze.Test.metadata(session).assigns.timing_run
    assert run.tracked_slide_index == 1
    assert hd(run.visits).duration_ms >= 1
    assert Enum.map(run.visits, & &1.slide_index) == [0, 1]

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})
    run = Breeze.Test.metadata(session).assigns.timing_run
    assert PresentationTiming.backtracking?(run)
    assert Enum.map(run.visits, & &1.slide_index) == [0, 1]

    Breeze.Test.event(session, nil, %{"ctrlKey" => true, "key" => "r"})
    Breeze.Test.input(session, "Enter")

    next_assigns = Breeze.Test.metadata(session).assigns
    assert next_assigns.expected_run.id == run.id
    assert next_assigns.timing_run.id != run.id
  end

  test "browses previous runs and selects expected per-slide timings" do
    metadata_dir = temporary_metadata_dir()
    on_exit(fn -> File.rm_rf(metadata_dir) end)
    deck = preview_deck()

    {:ok, run} =
      PresentationTiming.start_run(deck, 0, metadata_dir,
        now_ms: 0,
        now: "2026-08-21T10:00:00.000Z"
      )

    {:ok, run} =
      PresentationTiming.observe_slide(run, deck, 1,
        now_ms: 5_000,
        now: "2026-08-21T10:00:05.000Z"
      )

    {:ok, expected_run} =
      PresentationTiming.finish(run,
        now_ms: 10_000,
        now: "2026-08-21T10:00:10.000Z"
      )

    {:ok, older_run} =
      PresentationTiming.start_run(deck, 0, metadata_dir,
        now_ms: 0,
        now: "2026-08-20T09:00:00.000Z"
      )

    {:ok, older_run} =
      PresentationTiming.observe_slide(older_run, deck, 1,
        now_ms: 3_000,
        now: "2026-08-20T09:00:03.000Z"
      )

    {:ok, older_run} =
      PresentationTiming.finish(older_run,
        now_ms: 6_000,
        now: "2026-08-20T09:00:06.000Z"
      )

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula, metadata_dir: metadata_dir]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})

    assigns = Breeze.Test.metadata(session).assigns
    assert assigns.expected_run.id == expected_run.id
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "expected 00:05"

    Breeze.Test.input(session, "r")
    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "Previous Timing Runs"
    assert plain =~ "2026-08-21 10:00Z"
    assert plain =~ "00:10"
    assert plain =~ "2/2 slides"
    assert Breeze.Test.focused(session) == "timing-runs-list"

    assert {Breeze.Implicit.List, %{selected: selected_run_id, loop: false}} =
             Breeze.Test.metadata(session).implicit_state["timing-runs-list"]

    assert selected_run_id == expected_run.id

    Breeze.Test.input(session, "ArrowDown")
    assert Breeze.Test.metadata(session).assigns.timing_run_index == 1

    Breeze.Test.input(session, "Enter")
    assert Breeze.Test.metadata(session).assigns.expected_run.id == older_run.id

    Breeze.Test.input(session, "r")
    Breeze.Test.input(session, "c")
    assert is_nil(Breeze.Test.metadata(session).assigns.expected_run)

    Breeze.Test.input(session, "r")
    Breeze.Test.input(session, "Enter")
    assert Breeze.Test.metadata(session).assigns.expected_run.id == expected_run.id
  end

  test "title previews render text effects without animation overlay processes" do
    deck = title_preview_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {120, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})

    plain = session |> Breeze.Test.render!() |> strip_ansi()
    assert plain =~ "Static footer"
    assert plain =~ "Next footer"

    implicit_modules =
      session
      |> Breeze.Test.metadata()
      |> Map.fetch!(:implicit_state)
      |> Map.values()
      |> Enum.map(&elem(&1, 0))

    refute EasyBreezy.Implicit.TitleGradient in implicit_modules
    refute EasyBreezy.Implicit.TextShimmer in implicit_modules
  end

  test "p pauses and resumes the presentation timer" do
    sync_name = {:easy_breezy_pause_timer_test, System.unique_integer([:positive])}
    EasyBreezy.PresenterSync.register(sync_name)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, sync_name: sync_name]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_receive {:easy_breezy_presenter_subscribe, _pid}

    Breeze.Test.info(
      session,
      {:easy_breezy_presentation_state,
       presentation_payload(text_deck(), 0)
       |> Map.put(:elapsed_ms, 125_000)
       |> Map.put(:timer_paused?, false)}
    )

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "p")

    assigns = Breeze.Test.metadata(session).assigns
    assert assigns.timer_paused?
    assert is_integer(assigns.paused_elapsed_ms)
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Paused 02:05"
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "p resume"
    assert_receive {:easy_breezy_presenter_command, _pid, :toggle_timer_pause}

    Breeze.Test.info(session, :clock_tick)
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Paused 02:05"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "p")

    assigns = Breeze.Test.metadata(session).assigns
    refute assigns.timer_paused?
    assert is_nil(assigns.paused_elapsed_ms)
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Elapsed 02:05"
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "p pause"
    assert_receive {:easy_breezy_presenter_command, _pid, :toggle_timer_pause}
  end

  test "restores a paused timer from presentation state" do
    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      text_deck()
      |> presentation_payload(0)
      |> Map.merge(%{elapsed_ms: 125_000, timer_paused?: true})

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})

    assigns = Breeze.Test.metadata(session).assigns
    assert assigns.timer_paused?
    assert assigns.paused_elapsed_ms == 125_000
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Paused 02:05"
  end

  test "resubscribes when a reloaded presentation replaces its root process" do
    sync_name = {:easy_breezy_reload_test, System.unique_integer([:positive])}
    first = start_sync_target(sync_name, self())
    assert_receive {:sync_target_ready, ^first}, 1_000

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, sync_name: sync_name]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_receive {:sync_target_subscribed, ^first, presenter_pid}
    assert presenter_pid == session.pid

    Process.exit(first, :kill)
    second = start_sync_target(sync_name, self())
    assert_receive {:sync_target_ready, ^second}, 1_000

    assert_receive {:sync_target_subscribed, ^second, ^presenter_pid}, 1_000
    send(second, :stop)
  end

  test "cleans up kitty images when the visible image set changes" do
    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        terminal: recording_terminal(self()),
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, alt_screen: false]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(
      session,
      {:easy_breezy_presentation_state, presentation_payload(image_deck(), 0)}
    )

    assert_receive {:terminal_write, output}
    assert output == EasyBreezy.Slideshow.KittyImage.delete_command()

    Breeze.Test.info(
      session,
      {:easy_breezy_presentation_state, presentation_payload(image_deck(), 0)}
    )

    refute_receive {:terminal_write, _}, 50

    Breeze.Test.info(
      session,
      {:easy_breezy_presentation_state, presentation_payload(image_deck(), 1)}
    )

    assert_receive {:terminal_write, output}
    assert output == EasyBreezy.Slideshow.KittyImage.delete_command()
  end

  test "caps the next preview frame at the presentation width" do
    deck = preview_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {250, 70},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{screen_width: 86, screen_height: 23})

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})

    rendered = Breeze.Test.render!(session)
    plain = strip_ansi(rendered)

    assert plain =~ "Next: Why Breeze"

    assert plain =~
             "┌────────────────────────────────────────────────────────────────────────────────────┐ ┌Next: Why Breeze"
  end

  test "next markdown preview restores inline styles to its panel background" do
    deck = markdown_preview_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})

    rendered = Breeze.Test.render!(session)
    panel_restore = "\e[48;2;31;70;98;38;2;214;231;255m"
    surface_restore = "\e[48;2;25;53;73;38;2;214;231;255m"

    assert rendered =~ "\e[36m#{panel_restore} is th"
    refute rendered =~ "\e[36m#{surface_restore} is th"
  end

  test "next preview shows a placeholder for live slides" do
    deck = live_preview_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.put(:live_state, %{
        "breeze-slide-live-demo" => %{assigns: %{count: 7}}
      })

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "Next: Live Demo"
    assert plain =~ "Live Slide"
    assert plain =~ "Live Demo"
    refute plain =~ "value: 7"
    refute plain =~ "Live counter"
  end

  test "speaker notes render for code slides" do
    deck =
      Markdown.parse!("""
      ---
      layout: code
      title: File-backed Code
      language: elixir
      ---
      IO.puts(:ok)

      <!-- Mention the return value -->
      """)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "Speaker notes"
    assert plain =~ "Mention the return value"
    refute plain =~ "No notes for this slide."
  end

  test "speaker notes render for breeze slides" do
    deck =
      Markdown.parse!("""
      ---
      layout: breeze
      title: Counter Demo
      view: EasyBreezy.PresenterViewTest.LivePreviewView
      ---
      <!-- Demonstrate the live counter -->
      """)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "Speaker notes"
    assert plain =~ "Demonstrate the live counter"
    refute plain =~ "No notes for this slide."
  end

  test "sync payload elapsed time uses the local presenter clock" do
    deck = text_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{
        started_at_ms: System.monotonic_time(:millisecond) + 60_000,
        elapsed_ms: 125_000
      })

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "Elapsed 02:05"
    refute plain =~ "0-"
  end

  test "current preview renders slide source when the presentation is in source mode" do
    deck =
      Markdown.parse!("""
      ---
      layout: bullets
      title: Why
      ---
      - Rendered bullet
      """)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.put(:source_mode?, true)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "Why source"
    assert plain =~ "layout: bullets"
    assert plain =~ "- Rendered bullet"
    refute plain =~ "• Rendered bullet"
  end

  test "next preview activates kitty image overlays sized to the preview box" do
    path = Path.join(System.tmp_dir!(), "easy_breezy_presenter_preview.img")
    File.write!(path, "preview-image")
    deck = text_to_image_deck(path)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {120, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})

    rendered = Breeze.Test.render!(session)
    assert rendered =~ "Next: Image"

    assert {_module, state} = Breeze.Test.metadata(session).implicit_state["slide-image"]
    assert state.active?
    assert state.scope == "presenter-next:right"

    {:ok, _acc, _box, decorations} = Breeze.ChildServer.render_snapshot(session.pid, [])
    decoration = Enum.find(decorations, &(&1.id == "slide-image"))

    assert {:ok, _box, overlays: [overlay]} =
             decoration.mod.animate(:root, decoration.box, decoration.flags, decoration.state, %{
               phase: :async,
               frame: 0,
               layout: decoration.layout
             })

    assert overlay.width == decoration.layout.width - 2
    assert overlay.height == decoration.layout.height - 2
    assert overlay.content =~ "c=#{overlay.width},r=#{overlay.height}"
  end

  test "next preview renders a full-image slide edge to edge" do
    path = Path.join(System.tmp_dir!(), "easy_breezy_presenter_full_image.png")
    File.write!(path, "preview-image")
    deck = text_to_full_image_deck(path)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {120, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(session, {:easy_breezy_presentation_state, presentation_payload(deck, 0)})
    Breeze.Test.render!(session)

    assert {_module, state} = Breeze.Test.metadata(session).implicit_state["slide-image"]
    assert state.active?
    assert state.inset == 0
    assert state.scope == "presenter-next:full"

    {:ok, _acc, _box, decorations} = Breeze.ChildServer.render_snapshot(session.pid, [])
    decoration = Enum.find(decorations, &(&1.id == "slide-image"))

    assert {:ok, _box, overlays: [overlay]} =
             decoration.mod.animate(:root, decoration.box, decoration.flags, decoration.state, %{
               phase: :async,
               frame: 0,
               layout: decoration.layout
             })

    assert overlay.width == decoration.layout.width
    assert overlay.height == decoration.layout.height
  end

  test "next image preview keeps its image slot layout after a current live slide" do
    path = Path.join(System.tmp_dir!(), "easy_breezy_presenter_live_preview.img")
    File.write!(path, "preview-image")
    deck = live_to_image_deck(path)

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {204, 50},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{screen_width: 84, screen_height: 24})

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})

    {:ok, _acc, _box, decorations} =
      Breeze.ChildServer.render_snapshot(session.pid, terminal: session.terminal)

    decoration = Enum.find(decorations, &(&1.id == "slide-image"))

    assert %Breeze.Viewport{left: left, top: top, width: width, height: height} =
             decoration.layout

    assert left > 100
    assert top in 1..10
    assert width > 20
    assert height > 5

    assert {:ok, _box, overlays: [overlay]} =
             decoration.mod.animate(:root, decoration.box, decoration.flags, decoration.state, %{
               phase: :async,
               frame: 0,
               layout: decoration.layout
             })

    assert overlay.x == left + 1
    assert overlay.y == top + 1
    assert overlay.height == height - 2
  end

  test "arrow-key scrolling updates presenter scroll state and sends a presentation command" do
    sync_name = {:easy_breezy_test, System.unique_integer([:positive])}
    EasyBreezy.PresenterSync.register(sync_name)
    deck = long_bullets_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula, alt_screen: false, sync_name: sync_name]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_receive {:easy_breezy_presenter_subscribe, _pid}

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{step: 29, screen_width: 80, screen_height: 12})

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})
    Breeze.Test.render!(session)

    assert scroll_offset(session, "slide-bullets") == 0

    Breeze.Test.input(session, "ArrowDown")

    assert_receive {:easy_breezy_presenter_command, _pid, {:scroll, %{"key" => "ArrowDown"}}}

    assert scroll_offset(session, "slide-bullets") > 0
  end

  test "presentation scroll state payload syncs the presenter preview" do
    deck = long_bullets_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula, alt_screen: false]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{
        step: 29,
        screen_width: 80,
        screen_height: 12,
        scroll_state: %{"slide-bullets" => %{offset_y: 4, autoscroll: nil, pinned_bottom: false}}
      })

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})
    Breeze.Test.render!(session)

    assert scroll_offset(session, "slide-bullets") == 4
  end

  defp recording_terminal(owner) do
    %Termite.Terminal{
      adapter: {RecordingTerminal, %{owner: owner}},
      size: %{width: 100, height: 24}
    }
  end

  defp presentation_payload(deck, slide_index) do
    %{
      deck: deck,
      slide_index: slide_index,
      step: 0,
      screen_width: 100,
      screen_height: 24,
      theme_name: :nebula,
      actual_theme_mode: :custom,
      theme_status: :ready
    }
  end

  defp text_deck do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{id: :intro, title: "Intro", layout: :bullets, payload: text_payload("Intro")}
      ]
    }
  end

  defp image_deck do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{
          id: :image,
          title: "Image",
          layout: :two_column,
          payload:
            Map.merge(text_payload("Image"), %{right_mode: :image, right_path: "missing.png"})
        },
        %Slide{id: :outro, title: "Outro", layout: :bullets, payload: text_payload("Outro")}
      ]
    }
  end

  defp text_to_image_deck(path) do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{id: :intro, title: "Intro", layout: :bullets, payload: text_payload("Intro")},
        %Slide{
          id: :image,
          title: "Image",
          layout: :two_column,
          payload: Map.merge(text_payload("Image"), %{right_mode: :image, right_path: path})
        }
      ]
    }
  end

  defp text_to_full_image_deck(path) do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{id: :intro, title: "Intro", layout: :bullets, payload: text_payload("Intro")},
        %Slide{
          id: :full_image,
          title: "Full image",
          layout: :image,
          payload: %{path: path, alt: "Full image"}
        }
      ]
    }
  end

  defp live_to_image_deck(path) do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{
          id: :live_demo,
          title: "Live Demo",
          layout: :breeze,
          payload: LivePreviewView
        },
        %Slide{
          id: :image,
          title: "Image",
          layout: :two_column,
          payload:
            Map.merge(text_payload("Image"), %{
              right_title: "Image slot",
              right_mode: :image,
              right_path: path
            })
        }
      ]
    }
  end

  defp preview_deck do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{id: :title, title: "Title", layout: :bullets, payload: text_payload("Title")},
        %Slide{
          id: :why,
          title: "Why Breeze",
          layout: :bullets,
          payload: text_payload("Why Breeze")
        }
      ]
    }
  end

  defp title_preview_deck do
    %Deck{
      title: "Presenter Title Preview",
      slides: [
        %Slide{
          id: :current_title,
          title: "Current title",
          layout: :title,
          payload: %{title: "Current title", footer: "Static footer"}
        },
        %Slide{
          id: :next_title,
          title: "Next title",
          layout: :title,
          payload: %{title: "Next title", footer: "Next footer"}
        }
      ]
    }
  end

  defp markdown_preview_deck do
    markdown = "- `Termite.Screen` is the escape-sequence layer"

    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{id: :intro, title: "Intro", layout: :bullets, payload: text_payload("Intro")},
        %Slide{
          id: :termite_screen,
          title: "Termite Screen API",
          layout: :markdown,
          payload: %{
            title: "Termite Screen API",
            markdown: markdown,
            markdown_blocks: Markdown.content_blocks(markdown)
          }
        }
      ]
    }
  end

  defp live_preview_deck do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{id: :intro, title: "Intro", layout: :bullets, payload: text_payload("Intro")},
        %Slide{
          id: :live_demo,
          title: "Live Demo",
          layout: :breeze,
          payload: LivePreviewView
        }
      ]
    }
  end

  defp long_bullets_deck do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{
          id: :long,
          title: "Long",
          layout: :bullets,
          payload: %{title: "Long", items: Enum.map(1..30, &"Item #{&1}")},
          steps: 29
        }
      ]
    }
  end

  defp text_payload(title), do: %{title: title, items: ["One"]}

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")

  defp temporary_metadata_dir do
    Path.join(
      System.tmp_dir!(),
      "easy-breezy-presenter-timing-#{System.unique_integer([:positive, :monotonic])}"
    )
  end

  defp scroll_offset(session, id) do
    {Breeze.Implicit.Scroll, state} = Breeze.Test.metadata(session).implicit_state[id]
    state.offset_y
  end

  defp start_sync_target(sync_name, owner) do
    spawn(fn ->
      EasyBreezy.PresenterSync.register(sync_name)
      send(owner, {:sync_target_ready, self()})
      sync_target_loop(owner)
    end)
  end

  defp sync_target_loop(owner) do
    receive do
      {:easy_breezy_presenter_subscribe, presenter_pid} ->
        send(owner, {:sync_target_subscribed, self(), presenter_pid})
        sync_target_loop(owner)

      :stop ->
        :ok

      _message ->
        sync_target_loop(owner)
    end
  end
end
