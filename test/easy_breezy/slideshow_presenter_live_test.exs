defmodule EasyBreezy.SlideshowPresenterLiveTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  defmodule FakeAdapter do
    @behaviour Termite.Terminal.Adapter

    def start(_opts), do: {:ok, %{ref: make_ref(), size: %{width: 80, height: 24}}}
    def reader(term), do: {:ok, term.ref}
    def write(term, _str), do: {:ok, term}
    def resize(term), do: term.size
  end

  defmodule CounterView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 0)}

    def render(assigns) do
      ~H"""
      <box class="width-full height-full">
        <box class="bold text-primary">Counter</box>
        <box>value: {@count}</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => key}, term) when key in ["ArrowUp", "c"] do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _event, term), do: {:noreply, term}
  end

  defmodule DirectionView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, direction: "right", turns: 0)}

    def render(assigns) do
      ~H"""
      <box class="width-full height-full">
        <box class="bold text-primary">Snake</box>
        <box>direction: {@direction}</box>
        <box>turns: {@turns}</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => key}, term)
        when key in ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "h", "j", "k", "l"] do
      next_direction = direction_for_key(key)

      if next_direction == term.assigns.direction do
        {:noreply, term}
      else
        {:noreply, assign(term, direction: next_direction, turns: term.assigns.turns + 1)}
      end
    end

    def handle_event(_, _event, term), do: {:noreply, term}

    defp direction_for_key(key) when key in ["ArrowUp", "k"], do: "up"
    defp direction_for_key(key) when key in ["ArrowDown", "j"], do: "down"
    defp direction_for_key(key) when key in ["ArrowLeft", "h"], do: "left"
    defp direction_for_key(key) when key in ["ArrowRight", "l"], do: "right"
  end

  test "presentation payload includes the current live slide snapshot" do
    presentation = start_presentation(deck())
    on_exit(fn -> Breeze.Test.stop(presentation) end)

    Breeze.Test.render!(presentation)
    Breeze.Test.info(presentation, {:easy_breezy_presenter_subscribe, self()})

    payload = wait_for_payload(fn payload -> snapshot_content(payload) =~ "value: 0" end)

    assert payload.live_snapshot.id == "breeze-slide-counter"
    assert payload.live_snapshot.width == 74
    assert payload.live_snapshot.height == 18
    assert is_integer(payload.elapsed_ms)
    assert payload.elapsed_ms >= 0
  end

  test "presenter renders the presentation live snapshot and forwards regular input" do
    {presentation, presenter} = start_pair(deck())

    on_exit(fn ->
      Breeze.Test.stop(presenter)
      Breeze.Test.stop(presentation)
    end)

    assert eventually(fn -> render_plain(presenter) =~ "value: 0" end)

    assert {:noreply, _focused, _changed?} = Breeze.Test.input(presenter, "c")

    assert eventually(fn -> render_plain(presentation) =~ "value: 1" end)
    assert eventually(fn -> render_plain(presenter) =~ "value: 1" end)
  end

  test "presenter receives the live snapshot after subscribing before the presentation renders" do
    sync_name = {:easy_breezy_live_startup_test, System.unique_integer([:positive])}
    presentation = start_presentation(deck(), sync_name: sync_name)

    presenter =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck(), sync_name: sync_name, theme: :nebula]
      )

    on_exit(fn ->
      Breeze.Test.stop(presenter)
      Breeze.Test.stop(presentation)
    end)

    assert render_plain(presenter) =~ "Live Slide"
    refute render_plain(presenter) =~ "value: 0"

    Breeze.Test.render!(presentation)

    assert eventually(fn -> render_plain(presenter) =~ "value: 0" end)
  end

  test "presenter renders a live snapshot owned by the presentation server" do
    sync_name = {:easy_breezy_live_server_test, System.unique_integer([:positive])}
    presentation = start_server_presentation(deck(), sync_name: sync_name)

    presenter =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck(), sync_name: sync_name, theme: :nebula]
      )

    on_exit(fn ->
      Breeze.Test.stop(presenter)

      if Process.alive?(presentation) do
        GenServer.stop(presentation)
      end
    end)

    assert eventually(fn -> render_plain(presenter) =~ "value: 0" end)

    assert {:noreply, _focused, _changed?} = Breeze.Test.input(presenter, "ArrowUp")
    assert eventually(fn -> render_plain(presenter) =~ "value: 1" end)
  end

  test "presenter renders the live snapshot after presentation navigates into a live slide" do
    {presentation, presenter} = start_pair(plain_then_counter_deck())

    on_exit(fn ->
      Breeze.Test.stop(presenter)
      Breeze.Test.stop(presentation)
    end)

    assert eventually(fn -> render_plain(presenter) =~ "Plain" end)

    assert {:noreply, _focused, _changed?} = Breeze.Test.input(presentation, "ArrowRight")
    finish_transition(presentation)
    Breeze.Test.render!(presentation)

    assert eventually(fn -> render_plain(presenter) =~ "value: 0" end)
  end

  test "forwarded movement keys stay on the live slide when the child consumes them" do
    {presentation, presenter} = start_pair(direction_deck())

    on_exit(fn ->
      Breeze.Test.stop(presenter)
      Breeze.Test.stop(presentation)
    end)

    assert eventually(fn -> render_plain(presenter) =~ "direction: right" end)

    assert {:noreply, _focused, _changed?} = Breeze.Test.input(presenter, "ArrowUp")

    assert eventually(fn -> slide_index(presentation) == 0 end)
    assert eventually(fn -> render_plain(presentation) =~ "direction: up" end)
    assert eventually(fn -> render_plain(presenter) =~ "direction: up" end)
  end

  test "forwarded navigation keys advance when the live child does not consume them" do
    {presentation, presenter} = start_pair(two_slide_deck())

    on_exit(fn ->
      Breeze.Test.stop(presenter)
      Breeze.Test.stop(presentation)
    end)

    assert eventually(fn -> render_plain(presenter) =~ "value: 0" end)

    assert {:noreply, _focused, _changed?} = Breeze.Test.input(presenter, "ArrowRight")

    assert eventually(fn -> slide_index(presentation) == 1 end)
    assert eventually(fn -> render_plain(presenter) =~ "Plain" end)
  end

  test "unsynced live slides remain presenter placeholders and navigate normally" do
    {presentation, presenter} = start_pair(unsynced_then_plain_deck())

    on_exit(fn ->
      Breeze.Test.stop(presenter)
      Breeze.Test.stop(presentation)
    end)

    assert eventually(fn -> render_plain(presenter) =~ "Live Slide" end)
    refute render_plain(presenter) =~ "value: 0"

    assert {:noreply, _focused, _changed?} = Breeze.Test.input(presenter, "ArrowRight")

    assert eventually(fn -> slide_index(presentation) == 1 end)
    assert eventually(fn -> render_plain(presenter) =~ "Plain" end)
  end

  defp start_pair(deck) do
    sync_name = {:easy_breezy_live_forwarding_test, System.unique_integer([:positive])}

    presentation = start_presentation(deck, sync_name: sync_name)
    Breeze.Test.render!(presentation)

    presenter =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, sync_name: sync_name, theme: :nebula]
      )

    Breeze.Test.render!(presenter)

    {presentation, presenter}
  end

  defp start_presentation(deck, opts \\ []) do
    Breeze.Test.start!(EasyBreezy.Slideshow,
      size: {80, 24},
      theme: Breeze.Theme.builtin(:nebula),
      start_opts: [
        deck: deck,
        presenter_mode: :presentation,
        sync_name: Keyword.get(opts, :sync_name),
        themes: [:nebula],
        theme: :nebula
      ]
    )
  end

  defp start_server_presentation(deck, opts) do
    terminal = Termite.Terminal.start(adapter: FakeAdapter)

    {:ok, pid} =
      Breeze.Server.start_app_link(
        view: EasyBreezy.Slideshow,
        terminal: terminal,
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: deck,
          presenter_mode: :presentation,
          sync_name: Keyword.get(opts, :sync_name),
          themes: [:nebula],
          theme: :nebula
        ]
      )

    pid
  end

  defp deck do
    %Deck{
      title: "Presenter Live Test",
      slides: [
        %Slide{
          id: :counter,
          title: "Counter",
          layout: :breeze,
          payload: CounterView,
          disable_transitions?: true
        }
      ]
    }
  end

  defp two_slide_deck do
    %Deck{
      title: "Presenter Live Test",
      slides: [
        %Slide{
          id: :counter,
          title: "Counter",
          layout: :breeze,
          payload: CounterView,
          disable_transitions?: true
        },
        %Slide{
          id: :plain,
          title: "Plain",
          layout: :bullets,
          payload: %{title: "Plain", items: ["Other"]},
          disable_transitions?: true
        }
      ]
    }
  end

  defp direction_deck do
    %Deck{
      title: "Direction Test",
      slides: [
        %Slide{
          id: :snake,
          title: "Snake",
          layout: :breeze,
          payload: DirectionView,
          disable_transitions?: true
        },
        %Slide{
          id: :plain,
          title: "Plain",
          layout: :bullets,
          payload: %{title: "Plain", items: ["Other"]},
          disable_transitions?: true
        }
      ]
    }
  end

  defp plain_then_counter_deck do
    %Deck{
      title: "Presenter Live Test",
      slides: [
        %Slide{
          id: :plain,
          title: "Plain",
          layout: :bullets,
          payload: %{title: "Plain", items: ["Other"]},
          disable_transitions?: true
        },
        %Slide{
          id: :counter,
          title: "Counter",
          layout: :breeze,
          payload: CounterView,
          transition: :slide_up
        }
      ]
    }
  end

  defp unsynced_then_plain_deck do
    %Deck{
      title: "Presenter Live Test",
      slides: [
        %Slide{
          id: :counter,
          title: "Counter",
          layout: :breeze,
          payload: %{view: CounterView, sync_live_state: false},
          disable_transitions?: true
        },
        %Slide{
          id: :plain,
          title: "Plain",
          layout: :bullets,
          payload: %{title: "Plain", items: ["Other"]},
          disable_transitions?: true
        }
      ]
    }
  end

  defp wait_for_payload(fun, attempts \\ 20)

  defp wait_for_payload(fun, attempts) when attempts > 0 do
    receive do
      {:easy_breezy_presentation_state, payload} ->
        if fun.(payload), do: payload, else: wait_for_payload(fun, attempts - 1)
    after
      50 -> wait_for_payload(fun, attempts - 1)
    end
  end

  defp wait_for_payload(_fun, 0), do: flunk("timed out waiting for presentation payload")

  defp snapshot_content(%{live_snapshot: %{content: content}}), do: content
  defp snapshot_content(_payload), do: ""

  defp eventually(fun, attempts \\ 30)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false

  defp render_plain(session) do
    session
    |> Breeze.Test.render!()
    |> strip_ansi()
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")

  defp slide_index(session), do: Breeze.Test.metadata(session).assigns.slide_index

  defp finish_transition(session) do
    transition = Breeze.Test.metadata(session).assigns.transition

    if transition do
      for _ <- 0..transition.frames do
        send(session.pid, :transition_tick)
      end
    end
  end
end
