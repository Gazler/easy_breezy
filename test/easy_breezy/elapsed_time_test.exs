defmodule EasyBreezy.ElapsedTimeTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.ElapsedTime

  test "labels elapsed time" do
    assert ElapsedTime.label(1_000, 126_000) == "Elapsed 02:05"
  end

  test "clamps future start times" do
    label = ElapsedTime.label(10_000, 1_000)

    assert label == "Elapsed 00:00"
    refute label =~ "0-"
  end

  test "converts elapsed milliseconds into a local start time" do
    assert ElapsedTime.started_at_ms_from_elapsed(125_000, 200_000) == 75_000
    assert ElapsedTime.started_at_ms_from_elapsed(-1_000, 200_000) == 200_000
  end
end
