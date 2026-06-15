defmodule EasyBreezy.Implicit.TitleGradientTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Implicit.TitleGradient

  @started_at_ms 1_000
  @tick_ms 90
  @theme_colors %{
    primary: {10, 20, 30},
    secondary: {90, 100, 110},
    accent: {210, 40, 80}
  }

  test "async animation phase follows the retained start time" do
    state = title_gradient_state()
    box = BackBreeze.Box.new(content: "Breeze")

    async_frame_0 =
      TitleGradient.animate(:root, box, [], state, %{
        phase: :async,
        frame: 0,
        now: @started_at_ms + 37 * @tick_ms
      })

    explicit_frame_37 = TitleGradient.animate(:root, box, [], state, %{frame: 37})
    explicit_frame_0 = TitleGradient.animate(:root, box, [], state, %{frame: 0})

    assert async_frame_0 == explicit_frame_37
    refute async_frame_0 == explicit_frame_0
  end

  test "base render can preserve the elapsed animation phase" do
    box = BackBreeze.Box.new(content: "Breeze")
    state = title_gradient_state()

    base_frame_0 =
      TitleGradient.animate(:root, box, [], state, %{
        phase: :base,
        frame: 0,
        now: @started_at_ms + 37 * @tick_ms
      })

    explicit_frame_37 = TitleGradient.animate(:root, box, [], state, %{frame: 37})
    explicit_frame_0 = TitleGradient.animate(:root, box, [], state, %{frame: 0})

    assert base_frame_0 == explicit_frame_37
    refute base_frame_0 == explicit_frame_0
  end

  test "base render with previous layout updates content instead of returning an overlay" do
    box = BackBreeze.Box.new(content: "Breeze")
    state = title_gradient_state()

    base_frame_0 =
      TitleGradient.animate(:root, box, [], state, %{
        phase: :base,
        frame: 0,
        now: @started_at_ms + 37 * @tick_ms,
        layout: %Breeze.Viewport{left: 1, top: 1, width: 10, height: 2}
      })

    explicit_frame_37 = TitleGradient.animate(:root, box, [], state, %{frame: 37})
    explicit_frame_0 = TitleGradient.animate(:root, box, [], state, %{frame: 0})

    assert base_frame_0 == explicit_frame_37
    refute base_frame_0 == explicit_frame_0
  end

  defp title_gradient_state do
    {:ok, state, _meta} =
      TitleGradient.init(
        [],
        %{
          gradient_direction: "text-gradient-to-r",
          gradient_theme_colors: @theme_colors,
          gradient_background: {0, 0, 0},
          gradient_source: "Breeze"
        },
        %{started_at_ms: @started_at_ms}
      )

    state
  end
end
