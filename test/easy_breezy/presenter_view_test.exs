defmodule EasyBreezy.PresenterViewTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.Deck.Markdown
  alias EasyBreezy.{Deck, PresenterSync, Slide}
  alias EasyBreezy.PresenterSync.Session, as: PresentationSession

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
    {session, _presentation} =
      start_presenter(
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

    {session, _presentation} =
      start_presenter(
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, started_at_ms: started_at_ms]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.metadata(session).assigns.started_at_ms == started_at_ms
  end

  test "ctrl+r prompts before resetting the timer" do
    {session, presentation} =
      start_presenter(
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, nil, %{"ctrlKey" => true, "key" => "r"})

    assert Breeze.Test.metadata(session).assigns.reset_timer_modal?

    plain = session |> Breeze.Test.render!() |> strip_ansi()
    assert plain =~ "Reset Timer"
    assert plain =~ "Reset elapsed timer to 00:00?"

    refute_receive {:easy_breezy_presenter_command, ^presentation, _subscriber, :reset_timer}

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Escape")
    refute Breeze.Test.metadata(session).assigns.reset_timer_modal?
    refute session |> Breeze.Test.render!() |> strip_ansi() =~ "Reset Timer"

    refute_receive {:easy_breezy_presenter_command, ^presentation, _subscriber, :reset_timer}
  end

  test "confirming the reset timer prompt resets the local clock and presentation timer" do
    {session, presentation} =
      start_presenter(
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    old_started_at_ms = System.monotonic_time(:millisecond) - 125_000

    publish_state(
      presentation,
      session,
      1,
      presentation_payload(text_deck(), 0)
      |> Map.put(:elapsed_ms, 125_000)
      |> Map.put(:started_at_ms, old_started_at_ms)
    )

    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Elapsed 02:05"

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, nil, %{"ctrlKey" => true, "key" => "r"})

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Enter")

    refute Breeze.Test.metadata(session).assigns.reset_timer_modal?
    assert Breeze.Test.metadata(session).assigns.started_at_ms > old_started_at_ms
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Elapsed 00:00"

    assert_receive {:easy_breezy_presenter_command, ^presentation, presenter_pid, :reset_timer}
    assert presenter_pid == session.pid
  end

  test "resubscribes when a reloaded presentation replaces its root process" do
    sync_name = {:easy_breezy_reload_test, System.unique_integer([:positive])}
    first_producer = start_sync_target(sync_name, self())

    assert_receive {:sync_target_ready, ^first_producer, first_presentation}, 1_000

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, sync_name: sync_name]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_receive {:sync_target_subscribed, ^first_presentation, presenter_pid}
    assert presenter_pid == session.pid

    monitor_ref = Process.monitor(first_presentation)
    Process.exit(first_producer, :kill)
    assert_receive {:DOWN, ^monitor_ref, :process, ^first_presentation, _reason}, 1_000

    second_producer = start_sync_target(sync_name, self())

    assert_receive {:sync_target_ready, ^second_producer, second_presentation}, 1_000

    assert_receive {:sync_target_subscribed, ^second_presentation, ^presenter_pid}, 1_000
    send(second_producer, :stop)
  end

  test "keeps one presenter retry timer and ignores stale retry messages" do
    sync_name = {:easy_breezy_retry_test, System.unique_integer([:positive])}

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, sync_name: sync_name]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    first = Breeze.Test.metadata(session).assigns
    assert is_reference(first.presenter_retry_ref)
    assert is_reference(first.presenter_retry_token)

    Breeze.Test.info(session, {:presenter_sync_retry, first.presenter_retry_token})

    second = Breeze.Test.metadata(session).assigns
    assert is_reference(second.presenter_retry_ref)
    assert is_reference(second.presenter_retry_token)
    refute second.presenter_retry_ref == first.presenter_retry_ref
    refute second.presenter_retry_token == first.presenter_retry_token

    Breeze.Test.info(session, {:presenter_sync_retry, first.presenter_retry_token})

    current = Breeze.Test.metadata(session).assigns
    assert current.presenter_retry_ref == second.presenter_retry_ref
    assert current.presenter_retry_token == second.presenter_retry_token
  end

  test "cleans up kitty images when the visible image set changes" do
    {session, presentation} =
      start_presenter(
        terminal: recording_terminal(self()),
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, alt_screen: false]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    publish_state(
      presentation,
      session,
      1,
      presentation_payload(image_deck(), 0)
    )

    assert_receive {:terminal_write, output}
    assert output == EasyBreezy.Slideshow.KittyImage.delete_command()

    unchanged_payload = presentation_payload(image_deck(), 0)
    assert :ok = PresenterSync.publish(presentation, 2, unchanged_payload)

    assert eventually(fn ->
             PresentationSession.latest(presentation) == {2, unchanged_payload}
           end)

    refute_receive {:terminal_write, _}, 50

    publish_state(
      presentation,
      session,
      3,
      presentation_payload(image_deck(), 1)
    )

    assert_receive {:terminal_write, output}
    assert output == EasyBreezy.Slideshow.KittyImage.delete_command()
  end

  test "caps the next preview frame at the presentation width" do
    deck = preview_deck()

    {session, presentation} =
      start_presenter(
        size: {250, 70},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{screen_width: 86, screen_height: 23})

    publish_state(presentation, session, 1, payload)

    rendered = Breeze.Test.render!(session)
    plain = strip_ansi(rendered)

    assert plain =~ "Next: Why Breeze"

    assert plain =~
             "┌────────────────────────────────────────────────────────────────────────────────────┐ ┌Next: Why Breeze"
  end

  test "next preview shows a placeholder for live slides" do
    deck = live_preview_deck()

    {session, presentation} =
      start_presenter(
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

    publish_state(presentation, session, 1, payload)

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

    {session, presentation} =
      start_presenter(
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    publish_state(presentation, session, 1, presentation_payload(deck, 0))

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

    {session, presentation} =
      start_presenter(
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    publish_state(presentation, session, 1, presentation_payload(deck, 0))

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "Speaker notes"
    assert plain =~ "Demonstrate the live counter"
    refute plain =~ "No notes for this slide."
  end

  test "sync payload elapsed time uses the local presenter clock" do
    deck = text_deck()

    {session, presentation} =
      start_presenter(
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

    publish_state(presentation, session, 1, payload)

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

    {session, presentation} =
      start_presenter(
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.put(:source_mode?, true)

    publish_state(presentation, session, 1, payload)

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

    {session, presentation} =
      start_presenter(
        size: {120, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    publish_state(presentation, session, 1, presentation_payload(deck, 0))

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

    {session, presentation} =
      start_presenter(
        size: {120, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    publish_state(presentation, session, 1, presentation_payload(deck, 0))
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

    {session, presentation} =
      start_presenter(
        size: {204, 50},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{screen_width: 84, screen_height: 24})

    publish_state(presentation, session, 1, payload)

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
    deck = long_bullets_deck()

    {session, presentation} =
      start_presenter(
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula, alt_screen: false]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{step: 29, screen_width: 80, screen_height: 12})

    publish_state(presentation, session, 1, payload)
    Breeze.Test.render!(session)

    assert scroll_offset(session, "slide-bullets") == 0

    Breeze.Test.input(session, "ArrowDown")

    assert_receive {:easy_breezy_presenter_command, ^presentation, presenter_pid,
                    {:scroll, %{"key" => "ArrowDown"}}}

    assert presenter_pid == session.pid

    assert scroll_offset(session, "slide-bullets") > 0
  end

  test "presentation scroll state payload syncs the presenter preview" do
    deck = long_bullets_deck()

    {session, presentation} =
      start_presenter(
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

    publish_state(presentation, session, 1, payload)
    Breeze.Test.render!(session)

    assert scroll_offset(session, "slide-bullets") == 4
  end

  defp start_presenter(opts) do
    sync_name = {:presenter_view_test, System.unique_integer([:positive, :monotonic])}
    {:ok, presentation} = PresenterSync.start_presentation(sync_name)

    opts =
      Keyword.update!(opts, :start_opts, fn start_opts ->
        Keyword.put(start_opts, :sync_name, sync_name)
      end)

    presenter = Breeze.Test.start!(EasyBreezy.PresenterView, opts)

    assert eventually(fn -> PresentationSession.subscriber_count(presentation) == 1 end)

    {presenter, presentation}
  end

  defp publish_state(presentation, presenter, revision, payload) do
    assert :ok = PresenterSync.publish(presentation, revision, payload)

    assert eventually(fn ->
             Breeze.Test.metadata(presenter).assigns.presentation_revision == revision
           end)
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

  defp scroll_offset(session, id) do
    {Breeze.Implicit.Scroll, state} = Breeze.Test.metadata(session).implicit_state[id]
    state.offset_y
  end

  defp start_sync_target(sync_name, owner) do
    spawn(fn ->
      {:ok, presentation} = PresenterSync.start_presentation(sync_name)
      send(owner, {:sync_target_ready, self(), presentation})
      sync_target_loop(owner, presentation)
    end)
  end

  defp sync_target_loop(owner, presentation) do
    receive do
      {:easy_breezy_presenter_state_request, ^presentation, presenter_pid} ->
        send(owner, {:sync_target_subscribed, presentation, presenter_pid})
        sync_target_loop(owner, presentation)

      :stop ->
        :ok

      _message ->
        sync_target_loop(owner, presentation)
    end
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
