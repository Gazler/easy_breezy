defmodule EasyBreezy.SlideshowTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

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

    assert Breeze.Test.render!(session) =~ "space advance"

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "?")
    rendered = Breeze.Test.render!(session)

    refute rendered =~ "space advance"
    assert rendered |> strip_ansi() |> rendered_lines() |> List.last() |> String.starts_with?("└")

    assert {:noreply, _focused, true} = Breeze.Test.input(session, "?")
    assert Breeze.Test.render!(session) =~ "space advance"
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

  defp start_session(opts) do
    deck = Keyword.get(opts, :deck, deck())

    test_opts = [
      size: {80, 24},
      theme: Breeze.Theme.builtin(:nebula),
      start_opts: [
        deck: deck,
        alt_screen: false,
        themes: [:nebula],
        theme: :nebula
      ]
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
