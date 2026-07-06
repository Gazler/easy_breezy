defmodule EasyBreezy.CodeSlideTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Layouts.CodeSlide

  test "centers focused code in the visible code viewport" do
    source = Enum.map_join(1..50, "\n", &"line #{&1}")
    viewport_height = CodeSlide.code_viewport_height(14, "example.ex")

    snapshot =
      CodeSlide.render_snapshot(
        source,
        "text",
        "github_dark",
        %{},
        [{30, 30}],
        80,
        viewport_height
      )

    assert viewport_height == 10
    assert snapshot.target_scroll_y == 24
  end

  test "aligns oversized focus ranges to the first focused line" do
    source = Enum.map_join(1..50, "\n", &"line #{&1}")

    snapshot =
      CodeSlide.render_snapshot(
        source,
        "text",
        "github_dark",
        %{},
        [{20, 40}],
        80,
        10
      )

    assert snapshot.target_scroll_y == 19
  end

  test "sorts and merges focus ranges before choosing the scroll target" do
    source = Enum.map_join(1..50, "\n", &"line #{&1}")

    snapshot =
      CodeSlide.render_snapshot(
        source,
        "text",
        "github_dark",
        %{},
        [{30, 30}, 12, {14, 13}],
        80,
        10
      )

    assert snapshot.target_scroll_y == 7
  end

  test "resolves step-indexed focus range lists" do
    focus_ranges = [[], [4..6], [{8, 15}]]

    assert CodeSlide.step_count(focus_ranges) == 2
    assert CodeSlide.focus_ranges_for_step(focus_ranges, 0) == []
    assert CodeSlide.focus_ranges_for_step(focus_ranges, 1) == [4..6]
    assert CodeSlide.focus_ranges_for_step(focus_ranges, 2) == [{8, 15}]
  end

  test "preserves legacy focus range payloads" do
    focus_ranges = [{4, 6}]

    assert CodeSlide.step_count(focus_ranges) == nil
    assert CodeSlide.focus_ranges_for_step(focus_ranges, 2) == [{4, 6}]
  end
end
