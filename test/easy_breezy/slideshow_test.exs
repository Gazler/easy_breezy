defmodule EasyBreezy.SlideshowTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, PresenterSync, Slide}

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts) do
      {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    end

    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  defmodule RecordingAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(opts) do
      {:ok,
       %{ref: make_ref(), size: %{width: 100, height: 24}, owner: Keyword.fetch!(opts, :owner)}}
    end

    def reader(term), do: {:ok, term.ref}

    def write(term, output) do
      send(term.owner, {:terminal_write, output})
      {:ok, term}
    end

    def resize(term), do: term.size
  end

  test "g opens a slide number prompt and enter navigates to that slide" do
    session = start_session()
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render!(session) =~ "Slide 1/3"

    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "g")
    rendered = Breeze.Test.render!(session)
    assert rendered =~ "Go To Slide"
    assert rendered =~ "Enter slide"

    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "3")
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Enter")

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.slide_index == 2
    assert metadata.assigns.step == 0

    rendered = Breeze.Test.render!(session)
    assert rendered =~ "Slide 3/3"
    refute rendered =~ "Go To Slide"
  end

  test "invalid slide numbers keep the prompt open" do
    session = start_session()
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "g")
    assert {:noreply, "goto-slide-input", _dirty?} = Breeze.Test.input(session, "9")
    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "Enter")

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.slide_index == 0
    assert metadata.assigns.goto_modal? == true
    assert metadata.assigns.goto_slide_error == "Enter 1-3"

    rendered = Breeze.Test.render!(session)
    assert rendered =~ "Go To Slide"
    assert rendered =~ "Enter 1-3"
  end

  test "escape closes the slide number prompt" do
    session = start_session()
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "g")
    assert {:noreply, "goto-slide-input", _dirty?} = Breeze.Test.input(session, "2")
    assert Breeze.Test.render!(session) =~ "Go To Slide"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Escape")

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.goto_modal? == false
    assert metadata.assigns.goto_slide_input == ""
    assert metadata.assigns.slide_index == 0

    refute Breeze.Test.render!(session) =~ "Go To Slide"
  end

  test "? toggles the keybindings bar" do
    session = start_session()
    on_exit(fn -> Breeze.Test.stop(session) end)

    rendered = Breeze.Test.render!(session)
    refute rendered =~ "space advance"
    assert rendered |> strip_ansi() |> rendered_lines() |> List.last() |> String.starts_with?("└")

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "?")
    rendered = Breeze.Test.render!(session)
    assert rendered =~ "space advance"
    assert rendered =~ "T theme info"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "?")
    refute Breeze.Test.render!(session) =~ "space advance"
  end

  test "the keybindings bar can be shown initially" do
    session = start_session(start_opts: [keybindings_bar?: true])
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render!(session) =~ "space advance"
  end

  test "the header theme status is opt-in" do
    session = start_session()
    visible_session = start_session(start_opts: [theme_status?: true])

    on_exit(fn -> Breeze.Test.stop(session) end)
    on_exit(fn -> Breeze.Test.stop(visible_session) end)

    refute session |> Breeze.Test.render!() |> strip_ansi() =~ "nebula/custom (ready)"
    assert visible_session |> Breeze.Test.render!() |> strip_ansi() =~ "nebula/custom (ready)"
  end

  test "T toggles the header theme status" do
    session = start_session()
    on_exit(fn -> Breeze.Test.stop(session) end)

    refute session |> Breeze.Test.render!() |> strip_ansi() =~ "nebula/custom (ready)"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "T")
    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "nebula/custom (ready)"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "T")
    refute session |> Breeze.Test.render!() |> strip_ansi() =~ "nebula/custom (ready)"
  end

  test "escape does not close the slideshow" do
    session = start_session()
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, _focused, false} = Breeze.Test.input(session, "Escape")
    assert Process.alive?(session.pid)
  end

  test "presenter synchronization state is only assigned in presentation mode" do
    session = start_session()
    on_exit(fn -> Breeze.Test.stop(session) end)

    assigns = Breeze.Test.metadata(session).assigns

    refute Map.has_key?(assigns, :presenter_sync_name)
    refute Map.has_key?(assigns, :presenter_subscribers)
    refute Map.has_key?(assigns, :presenter_registry_monitor_ref)
    refute Map.has_key?(assigns, :presenter_registry_retry_ref)
    refute Map.has_key?(assigns, :presenter_live_sync)
  end

  test "a presentation registers again when the supervised registry restarts" do
    sync_name = {__MODULE__, :registry_restart, System.unique_integer([:positive, :monotonic])}

    session =
      start_session(start_opts: [presenter_mode: :presentation, sync_name: sync_name])

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert eventually(fn -> PresenterSync.whereis(sync_name) == session.pid end)

    old_registry = Process.whereis(EasyBreezy.PresenterSync.Scope)
    Process.exit(old_registry, :kill)

    assert eventually(fn ->
             registry = Process.whereis(EasyBreezy.PresenterSync.Scope)

             is_pid(registry) and registry != old_registry and
               PresenterSync.whereis(sync_name) == session.pid
           end)
  end

  test "the presenter reset command restarts the presentation timer" do
    session = start_session(start_opts: [presenter_mode: :presentation])
    on_exit(fn -> Breeze.Test.stop(session) end)

    started_at_ms = Breeze.Test.metadata(session).assigns.started_at_ms
    Process.sleep(2)

    Breeze.Test.info(
      session,
      {:easy_breezy_presenter_command, self(), :reset_timer}
    )

    assert Breeze.Test.metadata(session).assigns.started_at_ms == started_at_ms

    Breeze.Test.info(session, {:easy_breezy_presenter_subscribe, self()})

    Breeze.Test.info(
      session,
      {:easy_breezy_presenter_command, self(), :reset_timer}
    )

    assert Breeze.Test.metadata(session).assigns.started_at_ms > started_at_ms
  end

  test "i toggles the current slide markdown source" do
    deck =
      EasyBreezy.Deck.Markdown.parse!("""
      ---
      layout: bullets
      title: Why
      ---
      - Rendered bullet
      """)

    session = start_session(deck: deck)
    on_exit(fn -> Breeze.Test.stop(session) end)

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "• Rendered bullet"
    refute plain =~ "layout: bullets"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "i")

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "Why source"
    assert plain =~ "layout: bullets"
    assert plain =~ "- Rendered bullet"
    refute plain =~ "• Rendered bullet"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "i")

    plain = session |> Breeze.Test.render!() |> strip_ansi()

    assert plain =~ "• Rendered bullet"
    refute plain =~ "layout: bullets"
  end

  test "e opens a modal editor in source mode and :w applies in-memory changes" do
    session = start_session(deck: EasyBreezy.Deck.Markdown.parse!("# Old"))
    on_exit(fn -> Breeze.Test.stop(session) end)

    input_keys(session, ["i", "e"])

    plain = session |> Breeze.Test.render!() |> strip_ansi()
    assert plain =~ "Vim-like editor"
    assert plain =~ "NORMAL"

    input_keys(session, ["$", "a", " updated", "Escape", ":", "w", "Enter"])

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.deck.source == "# Old updated"
    assert hd(metadata.assigns.deck.slides).title == "Old updated"
    assert metadata.assigns.source_editor.dirty? == false

    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Updated in memory"
  end

  test "restores a save flash after the slideshow reloads" do
    session =
      start_session(start_opts: [source_save_notice: %{id: 1, message: "Slide source written"}])

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert session |> Breeze.Test.render!() |> strip_ansi() =~ "Slide source written"
    refute Map.has_key?(Breeze.Test.metadata(session).assigns, :source_save_notice)
  end

  test "carries a save notice through refreshed server options" do
    notice = %{id: 1, message: "Slide source written"}

    assert [start_opts: start_opts] =
             EasyBreezy.refresh_server_opts(
               [deck: fn -> deck() end],
               %{metadata: %{assigns: %{source_save_notice: notice}}}
             )

    assert Keyword.fetch!(start_opts, :source_save_notice) == notice
  end

  test "preserves the presentation timer through refreshed server options" do
    started_at_ms = System.monotonic_time(:millisecond) - 125_000

    assert [start_opts: start_opts] =
             EasyBreezy.refresh_server_opts(
               [deck: fn -> deck() end],
               %{metadata: %{assigns: %{started_at_ms: started_at_ms}}}
             )

    assert Keyword.fetch!(start_opts, :started_at_ms) == started_at_ms

    session = start_session(start_opts: start_opts)
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.metadata(session).assigns.started_at_ms == started_at_ms
  end

  test "passes the header theme status option through to the slideshow" do
    assert [start_opts: start_opts] =
             EasyBreezy.refresh_server_opts(
               [deck: fn -> deck() end, theme_status?: true],
               %{}
             )

    assert Keyword.fetch!(start_opts, :theme_status?)
  end

  test "preserves toggled header theme status through refreshed server options" do
    assert [start_opts: start_opts] =
             EasyBreezy.refresh_server_opts(
               [deck: fn -> deck() end, theme_status?: false],
               %{metadata: %{assigns: %{theme_status?: true}}}
             )

    assert Keyword.fetch!(start_opts, :theme_status?)
  end

  test ":q leaves the editor and returns to the rendered slide" do
    session = start_session(deck: EasyBreezy.Deck.Markdown.parse!("# Rendered"))
    on_exit(fn -> Breeze.Test.stop(session) end)

    input_keys(session, ["i", "e", ":", "q", "Enter"])

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.source_editor == nil
    assert metadata.assigns.source_mode? == false

    plain = session |> Breeze.Test.render!() |> strip_ansi()
    assert plain =~ "# Rendered"
    refute plain =~ "Rendered source"
    refute plain =~ "Vim-like editor"
  end

  test ":w writes a file-backed deck and :wq closes the editor" do
    path =
      Path.join(System.tmp_dir!(), "easy-breezy-edit-#{System.unique_integer([:positive])}.md")

    File.write!(path, "# Old")
    on_exit(fn -> File.rm(path) end)

    session = start_session(deck: EasyBreezy.Deck.Loader.load!(path))
    on_exit(fn -> Breeze.Test.stop(session) end)

    input_keys(session, ["i", "e", "d", "d", "i", "# New", "Escape", ":", "wq", "Enter"])

    assert File.read!(path) == "# New"

    metadata = Breeze.Test.metadata(session)
    assert hd(metadata.assigns.deck.slides).title == "New"
    assert metadata.assigns.source_editor == nil
    assert metadata.assigns.source_mode? == false

    plain = session |> Breeze.Test.render!() |> strip_ansi()
    assert plain =~ "New"
    refute plain =~ "New source"
    assert plain =~ "Slide source written"
  end

  test ":w keeps invalid markdown in the editor without changing the deck file" do
    source = "---\nlayout: bullets\ntitle: Old\n---\n- item"

    path =
      Path.join(System.tmp_dir!(), "easy-breezy-invalid-#{System.unique_integer([:positive])}.md")

    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)

    session = start_session(deck: EasyBreezy.Deck.Loader.load!(path))
    on_exit(fn -> Breeze.Test.stop(session) end)

    input_keys(session, ["i", "e", "j"] ++ List.duplicate("l", 6) ++ ["x", ":", "w", "Enter"])

    assert File.read!(path) == source

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.source_editor.dirty?
    assert metadata.assigns.source_editor.message =~ "invalid slide frontmatter"
  end

  test "raw escape closes the slide number prompt while the input is focused" do
    session = start_session()
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "g")
    assert {:noreply, "goto-slide-input", _dirty?} = Breeze.Test.input(session, "2")

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "\e")

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.goto_modal? == false
    assert metadata.assigns.goto_slide_input == ""

    refute Breeze.Test.render!(session) =~ "Go To Slide"
  end

  test "enhanced keyboard escape closes the slide number prompt through the server input path" do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)
    reader = terminal.reader

    {:ok, server} =
      Breeze.Server.start_app_link(
        view: EasyBreezy.Slideshow,
        terminal: terminal,
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: deck(),
          themes: [:nebula],
          theme: :nebula
        ],
        global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
      )

    on_exit(fn -> if Process.alive?(server), do: GenServer.stop(server, :normal) end)

    send_server_input(server, reader, "g")
    metadata = server_metadata(server)
    assert metadata.assigns.goto_modal? == true
    assert metadata.focused == "goto-slide-input"

    send_server_input(server, reader, "\e[27u")
    metadata = server_metadata(server)
    assert metadata.assigns.goto_modal? == false
    assert metadata.assigns.goto_slide_input == ""
  end

  test "g jump from an image slide deletes the kitty image overlay" do
    session = start_session(deck: image_to_text_deck(), terminal: recording_terminal(self()))
    on_exit(fn -> Breeze.Test.stop(session) end)

    flush_terminal_writes()

    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "g")
    _rendered = Breeze.Test.render!(session)
    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "2")
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Enter")

    assert_receive {:terminal_write, output}
    assert output == EasyBreezy.Slideshow.KittyImage.delete_command()

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.slide_index == 1
  end

  test "g jump to the current image slide is a noop" do
    session = start_session(deck: image_to_text_deck(), terminal: recording_terminal(self()))
    on_exit(fn -> Breeze.Test.stop(session) end)

    flush_terminal_writes()

    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "g")
    _rendered = Breeze.Test.render!(session)
    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "1")
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Enter")

    refute_receive {:terminal_write, _}

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.slide_index == 0
    assert metadata.assigns.step == 0
    assert metadata.assigns.goto_modal? == false
  end

  test "g jump to an image slide keeps the destination kitty image overlay" do
    session = start_session(deck: text_to_image_deck(), terminal: recording_terminal(self()))
    on_exit(fn -> Breeze.Test.stop(session) end)

    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "g")
    _rendered = Breeze.Test.render!(session)
    assert {:noreply, "goto-slide-input", true} = Breeze.Test.input(session, "2")
    assert {:noreply, _focused, true} = Breeze.Test.input(session, "Enter")

    refute_receive {:terminal_write, _}

    metadata = Breeze.Test.metadata(session)
    assert metadata.assigns.slide_index == 1
  end

  defp start_session do
    start_session([])
  end

  defp input_keys(session, keys) do
    Enum.each(keys, fn key ->
      assert {:noreply, _focused, _changed?} = Breeze.Test.input(session, key)
    end)
  end

  defp eventually(fun, attempts \\ 40)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false

  defp start_session(opts) do
    deck = Keyword.get(opts, :deck, deck())

    start_opts =
      Keyword.merge(
        [
          deck: deck,
          alt_screen: false,
          themes: [:nebula],
          theme: :nebula
        ],
        Keyword.get(opts, :start_opts, [])
      )

    test_opts = [
      size: {80, 24},
      theme: Breeze.Theme.builtin(:nebula),
      start_opts: start_opts
    ]

    test_opts =
      if terminal = Keyword.get(opts, :terminal) do
        Keyword.put(test_opts, :terminal, terminal)
      else
        test_opts
      end

    Breeze.Test.start!(EasyBreezy.Slideshow, test_opts)
  end

  defp deck do
    %Deck{
      title: "Keyboard Deck",
      slides:
        for number <- 1..3 do
          title = "Slide #{number}"

          %Slide{
            id: :"slide_#{number}",
            title: title,
            layout: :bullets,
            payload: %{title: title, items: []},
            disable_transitions?: true
          }
        end
    }
  end

  defp image_to_text_deck do
    %Deck{
      title: "Image Jump Deck",
      slides: [
        image_slide(),
        text_slide(:outro, "Outro")
      ]
    }
  end

  defp text_to_image_deck do
    %Deck{
      title: "Image Jump Deck",
      slides: [
        text_slide(:intro, "Intro"),
        image_slide()
      ]
    }
  end

  defp image_slide do
    %Slide{
      id: :image,
      title: "Image",
      layout: :two_column,
      payload: %{title: "Image", left_lines: [], right_mode: :image, right_path: "missing.png"},
      disable_transitions?: true
    }
  end

  defp text_slide(id, title) do
    %Slide{
      id: id,
      title: title,
      layout: :bullets,
      payload: %{title: title, items: []},
      disable_transitions?: true
    }
  end

  defp recording_terminal(owner) do
    Termite.Terminal.start(adapter: RecordingAdapter, owner: owner)
  end

  defp flush_terminal_writes do
    receive do
      {:terminal_write, _output} -> flush_terminal_writes()
    after
      0 -> :ok
    end
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")

  defp rendered_lines(text), do: String.split(text, "\n", trim: false)

  defp send_server_input(server, reader, raw) do
    send(server, {reader, {:data, raw}})

    wait_until(fn ->
      state = :sys.get_state(server)
      not state.input.flush_scheduled? and :queue.is_empty(state.input.queued_input)
    end)
  end

  defp server_metadata(server) do
    server
    |> :sys.get_state()
    |> Map.fetch!(:view_pid)
    |> Breeze.ChildServer.metadata()
  end

  defp wait_until(fun, attempts \\ 100)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: flunk("timed out waiting for server input flush")
end
