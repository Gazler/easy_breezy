defmodule EasyBreezy.TransitionsTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Transitions
  alias EasyBreezy.Slide

  test "uses enough frames for small terminal transitions" do
    assert Transitions.transition_frames(74) == 16
  end

  test "slows small terminal transitions without slowing large terminals" do
    small_frames = Transitions.transition_frames(74)
    small_total = small_frames * Transitions.transition_interval_ms(:forward, 74, small_frames)

    large_frames = Transitions.transition_frames(240)
    large_total = large_frames * Transitions.transition_interval_ms(:forward, 240, large_frames)

    assert small_total in 380..420
    assert large_total <= 220
  end

  test "keeps zoomed-in transitions slow enough to read" do
    frames = Transitions.transition_frames(20)
    total = frames * Transitions.transition_interval_ms(:forward, 20, frames)

    assert total in 380..420
  end

  test "skips overdue frames to keep the transition on wall-clock time" do
    transition = %{
      frame: 0,
      frames: 16,
      interval_ms: 25,
      started_at_ms: 1_000
    }

    assert Transitions.next_frame(transition, 1_025) == 1
    assert Transitions.next_frame(%{transition | frame: 1}, 1_080) == 3
    assert Transitions.next_frame(%{transition | frame: 3}, 1_400) == 16
  end

  test "schedules the next frame against the transition start time" do
    transition = %{
      frame: 3,
      frames: 16,
      interval_ms: 25,
      started_at_ms: 1_000
    }

    assert Transitions.next_tick_at_ms(transition) == 1_100
    assert Transitions.next_tick_delay_ms(transition, 1_080) == 20
    assert Transitions.next_tick_delay_ms(transition, 1_120) == 0
  end

  test "disables transitions when either slide is a full image" do
    image = %Slide{layout: :image}
    text = %Slide{layout: :bullets}

    refute Transitions.enabled?(image, text, :forward, :dark)
    refute Transitions.enabled?(text, image, :forward, :dark)
  end
end
