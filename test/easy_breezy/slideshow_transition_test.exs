defmodule EasyBreezy.SlideshowTransitionTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  test "freezes animated text at its transition-start frame" do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {80, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: transition_deck(),
          themes: [:nebula],
          theme: :nebula
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    _initial_render = Breeze.Test.render!(session)

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, nil, %{"key" => "ArrowRight"})

    _rendered = Breeze.Test.render!(session)

    metadata = Breeze.Test.metadata(session)

    assert transition = metadata.assigns.transition

    assert {gradient_id, {EasyBreezy.Implicit.TitleGradient, gradient_state}} =
             title_gradient(metadata.implicit_state)

    assert {shimmer_id, {EasyBreezy.Implicit.TextShimmer, shimmer_state}} =
             text_shimmer(metadata.implicit_state)

    assert gradient_state.frozen_now == transition.animation_frozen_now
    assert shimmer_state.frozen_now == transition.animation_frozen_now
    assert Map.get(metadata.implicit_meta, gradient_id, %{}) == %{}
    assert Map.get(metadata.implicit_meta, shimmer_id, %{}) == %{}

    frozen_gradient_frame =
      EasyBreezy.Implicit.TitleGradient.elapsed_frame(
        gradient_state.started_at_ms,
        gradient_state.frozen_now
      )

    frozen_shimmer_frame =
      EasyBreezy.Implicit.TextShimmer.elapsed_frame(
        shimmer_state.started_at_ms,
        shimmer_state.frozen_now
      )

    send(session.pid, :transition_tick)
    _rendered = Breeze.Test.render!(session)

    next_metadata = Breeze.Test.metadata(session)

    assert {^gradient_id, {EasyBreezy.Implicit.TitleGradient, next_gradient_state}} =
             title_gradient(next_metadata.implicit_state)

    assert {^shimmer_id, {EasyBreezy.Implicit.TextShimmer, next_shimmer_state}} =
             text_shimmer(next_metadata.implicit_state)

    assert next_gradient_state.frozen_now == gradient_state.frozen_now
    assert next_shimmer_state.frozen_now == shimmer_state.frozen_now
    assert Map.get(next_metadata.implicit_meta, gradient_id, %{}) == %{}
    assert Map.get(next_metadata.implicit_meta, shimmer_id, %{}) == %{}

    assert EasyBreezy.Implicit.TitleGradient.elapsed_frame(
             next_gradient_state.started_at_ms,
             next_gradient_state.frozen_now
           ) == frozen_gradient_frame

    assert EasyBreezy.Implicit.TextShimmer.elapsed_frame(
             next_shimmer_state.started_at_ms,
             next_shimmer_state.frozen_now
           ) == frozen_shimmer_frame
  end

  defp title_gradient(implicit_state) do
    Enum.find(implicit_state, fn
      {"title-gradient-" <> _, {EasyBreezy.Implicit.TitleGradient, _state}} -> true
      _other -> nil
    end)
  end

  defp text_shimmer(implicit_state) do
    Enum.find(implicit_state, fn
      {"footer-shimmer-" <> _, {EasyBreezy.Implicit.TextShimmer, _state}} -> true
      _other -> nil
    end)
  end

  defp transition_deck do
    %Deck{
      title: "Transition Test Deck",
      slides: [
        %Slide{
          id: :title,
          title: "Breeze",
          layout: :title,
          payload: %{
            title: "Breeze",
            subtitle: "Transition gradient",
            speaker: "Gazler",
            footer: "Terminal-native slides"
          },
          transition: :slide
        },
        %Slide{
          id: :next,
          title: "Next",
          layout: :bullets,
          payload: %{
            title: "Next",
            items: ["The title slide is transitioning out."]
          },
          transition: :slide
        }
      ]
    }
  end
end
