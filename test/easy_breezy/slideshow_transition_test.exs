defmodule EasyBreezy.SlideshowTransitionTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}
  alias EasyBreezy.Implicit.TitleGradient

  @tick_ms 90

  test "keeps the title gradient active during slide transitions" do
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

    Process.sleep(3 * @tick_ms)

    assert {:noreply, _focused, true} =
             Breeze.Test.event(session, nil, %{"key" => "ArrowRight"})

    rendered = Breeze.Test.render!(session)

    metadata = Breeze.Test.metadata(session)

    assert metadata.assigns.transition
    assert {_id, {_mod, state}} = title_gradient(metadata.implicit_state)
    assert is_integer(state.started_at_ms)

    frame = TitleGradient.elapsed_frame(state.started_at_ms, System.monotonic_time(:millisecond))

    assert frame > 0
    assert rendered_gradient_frame?(rendered, state.theme_colors, frame)
  end

  defp title_gradient(implicit_state) do
    Enum.find(implicit_state, fn
      {"title-gradient-" <> _, {EasyBreezy.Implicit.TitleGradient, _state}} -> true
      _other -> nil
    end)
  end

  defp rendered_gradient_frame?(rendered, theme_colors, frame) do
    first_frame = max(frame - 2, 1)

    Enum.any?(first_frame..(frame + 1), fn frame ->
      with {:ok, from, _to} <- TitleGradient.colors(theme_colors, frame) do
        rendered =~ ansi_foreground(from)
      end
    end)
  end

  defp ansi_foreground({red, green, blue}), do: "38;2;#{red};#{green};#{blue}m"

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
