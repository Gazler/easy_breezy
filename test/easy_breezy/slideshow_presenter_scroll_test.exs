defmodule EasyBreezy.SlideshowPresenterScrollTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

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
    Breeze.Test.info(session, {:easy_breezy_presenter_subscribe, self()})

    Breeze.Test.info(
      session,
      {:easy_breezy_presenter_command, self(), {:scroll, %{"key" => "PageDown"}}}
    )

    assert scroll_offset(session, "slide-bullets") == 0

    Breeze.Test.info(
      session,
      {:easy_breezy_presenter_command, self(), {:scroll, %{"key" => "ArrowDown"}}}
    )

    assert scroll_offset(session, "slide-bullets") > 0
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
    Breeze.Test.info(session, {:easy_breezy_presenter_subscribe, self()})

    assert_receive {:easy_breezy_presentation_state, %{scroll_state: initial_scroll_state}}
    assert initial_scroll_state["slide-bullets"].offset_y == 0

    Breeze.Test.input(session, "ArrowDown")

    assert_receive {:easy_breezy_presentation_state, %{scroll_state: next_scroll_state}}
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
end
