defmodule EasyBreezy.SlideshowPresenterScrollTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, PresenterSync, Slide}

  test "presenter scroll commands update presentation scroll state" do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {80, 12},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: long_bullets_deck(),
          presenter_mode: :presentation,
          step: 29,
          themes: [:nebula],
          theme: :nebula
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.render!(session)

    assert scroll_offset(session, "slide-bullets") == 0

    presenter_session = presenter_session(session)
    assert {:ok, ^presenter_session} = PresenterSync.subscribe(presenter_session)
    assert :ok = PresenterSync.command(presenter_session, {:scroll, %{"key" => "ArrowDown"}})

    assert eventually(fn -> scroll_offset(session, "slide-bullets") > 0 end)
  end

  test "presentation arrow-key scrolling publishes scroll state for presenter sync" do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {80, 12},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: long_bullets_deck(),
          presenter_mode: :presentation,
          step: 29,
          themes: [:nebula],
          theme: :nebula
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.render!(session)
    presenter_session = presenter_session(session)
    assert {:ok, ^presenter_session} = PresenterSync.subscribe(presenter_session)

    initial_scroll_state =
      wait_for_scroll_state(presenter_session, fn scroll_state ->
        get_in(scroll_state, ["slide-bullets", :offset_y]) == 0
      end)

    assert initial_scroll_state["slide-bullets"].offset_y == 0

    Breeze.Test.input(session, "ArrowDown")

    next_scroll_state =
      wait_for_scroll_state(presenter_session, fn scroll_state ->
        (get_in(scroll_state, ["slide-bullets", :offset_y]) || 0) > 0
      end)

    assert next_scroll_state["slide-bullets"].offset_y > 0
  end

  defp long_bullets_deck do
    %Deck{
      title: "Presenter Scroll Test",
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

  defp scroll_offset(session, id) do
    {Breeze.Implicit.Scroll, state} = Breeze.Test.metadata(session).implicit_state[id]
    state.offset_y
  end

  defp presenter_session(session) do
    Breeze.Test.metadata(session).assigns.presenter_session_pid
  end

  defp wait_for_scroll_state(presenter_session, fun, attempts \\ 30)

  defp wait_for_scroll_state(presenter_session, fun, attempts) when attempts > 0 do
    receive do
      {:easy_breezy_presentation_state, ^presenter_session, _revision,
       %{scroll_state: scroll_state}} ->
        if fun.(scroll_state) do
          scroll_state
        else
          wait_for_scroll_state(presenter_session, fun, attempts - 1)
        end
    after
      50 -> wait_for_scroll_state(presenter_session, fun, attempts - 1)
    end
  end

  defp wait_for_scroll_state(_presenter_session, _fun, 0),
    do: flunk("timed out waiting for presenter scroll state")

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
end
