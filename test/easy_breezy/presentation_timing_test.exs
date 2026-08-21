defmodule EasyBreezy.PresentationTimingTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.{Deck, PresentationTiming, Slide}

  setup do
    metadata_dir =
      Path.join(
        System.tmp_dir!(),
        "easy-breezy-timing-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf(metadata_dir) end)
    {:ok, metadata_dir: metadata_dir}
  end

  test "records slide enter and leave times and persists a completed run", %{
    metadata_dir: metadata_dir
  } do
    {:ok, run} =
      PresentationTiming.start_run(deck(), 0, metadata_dir,
        now_ms: 1_000,
        now: "2026-08-21T10:00:00.000Z"
      )

    assert File.regular?(run.path)
    assert Path.extname(run.path) == ".json"
    assert run.tracked_slide_index == 0

    active_data = run.path |> File.read!() |> Jason.decode!()
    assert active_data["status"] == "active"

    assert active_data["visits"] == [
             %{
               "duration_ms" => nil,
               "entered_at" => "2026-08-21T10:00:00.000Z",
               "left_at" => nil,
               "slide_id" => "intro",
               "slide_index" => 0,
               "title" => "Intro"
             }
           ]

    {:ok, run} =
      PresentationTiming.observe_slide(run, deck(), 1,
        now_ms: 6_000,
        now: "2026-08-21T10:00:05.000Z"
      )

    changed_data = run.path |> File.read!() |> Jason.decode!()
    assert get_in(changed_data, ["visits", Access.at(0), "duration_ms"]) == 5_000
    assert get_in(changed_data, ["visits", Access.at(1), "duration_ms"]) == nil

    {:ok, run} =
      PresentationTiming.finish(run,
        now_ms: 10_000,
        now: "2026-08-21T10:00:09.000Z"
      )

    assert run.status == :complete
    assert Enum.map(run.visits, & &1.slide_index) == [0, 1]

    assert [first, second] = run.visits
    assert first.entered_at == "2026-08-21T10:00:00.000Z"
    assert first.left_at == "2026-08-21T10:00:05.000Z"
    assert first.duration_ms == 5_000
    assert second.duration_ms == 4_000

    contents = File.read!(run.path)
    assert String.starts_with?(contents, "{\n  ")

    completed_data = Jason.decode!(contents)
    assert completed_data["version"] == 1
    assert completed_data["status"] == "complete"
    assert completed_data["total_duration_ms"] == 9_000

    assert completed_data["deck"]["slides"] |> Enum.map(& &1["id"]) ==
             ["intro", "middle", "outro"]

    assert [stored] = PresentationTiming.list_runs(metadata_dir, deck())
    assert PresentationTiming.complete?(stored)
    assert PresentationTiming.total_duration_ms(stored) == 9_000
    assert PresentationTiming.expected_duration_ms(stored, 0) == 5_000
    assert PresentationTiming.expected_duration_ms(stored, 1) == 4_000
  end

  test "ignores backward slides and excludes the detour from forward timings", %{
    metadata_dir: metadata_dir
  } do
    {:ok, run} =
      PresentationTiming.start_run(deck(), 0, metadata_dir,
        now_ms: 0,
        now: "2026-08-21T10:00:00.000Z"
      )

    {:ok, run} =
      PresentationTiming.observe_slide(run, deck(), 1,
        now_ms: 10_000,
        now: "2026-08-21T10:00:10.000Z"
      )

    {:ok, run} =
      PresentationTiming.observe_slide(run, deck(), 0,
        now_ms: 14_000,
        now: "2026-08-21T10:00:14.000Z"
      )

    assert PresentationTiming.backtracking?(run)
    assert PresentationTiming.current_duration_ms(run, 60_000) == 4_000

    {:ok, run} =
      PresentationTiming.observe_slide(run, deck(), 2,
        now_ms: 70_000,
        now: "2026-08-21T10:01:10.000Z"
      )

    refute PresentationTiming.backtracking?(run)
    assert Enum.map(run.visits, & &1.slide_index) == [0, 1, 2]

    second = Enum.at(run.visits, 1)
    assert second.duration_ms == 4_000
    assert second.left_at == "2026-08-21T10:00:14.000Z"
    assert PresentationTiming.current_duration_ms(run, 72_000) == 2_000
  end

  test "resumes the high-water slide without counting time spent going backwards", %{
    metadata_dir: metadata_dir
  } do
    {:ok, run} =
      PresentationTiming.start_run(deck(), 1, metadata_dir,
        now_ms: 1_000,
        now: "2026-08-21T10:00:00.000Z"
      )

    {:ok, run} =
      PresentationTiming.observe_slide(run, deck(), 0,
        now_ms: 5_000,
        now: "2026-08-21T10:00:04.000Z"
      )

    {:ok, run} =
      PresentationTiming.observe_slide(run, deck(), 1,
        now_ms: 25_000,
        now: "2026-08-21T10:00:24.000Z"
      )

    {:ok, run} =
      PresentationTiming.observe_slide(run, deck(), 2,
        now_ms: 28_000,
        now: "2026-08-21T10:00:27.000Z"
      )

    assert Enum.at(run.visits, 0).duration_ms == 7_000
    assert Enum.map(run.visits, & &1.slide_index) == [1, 2]
  end

  test "only lists runs belonging to the current deck", %{metadata_dir: metadata_dir} do
    {:ok, run} =
      PresentationTiming.start_run(deck(), 0, metadata_dir,
        now_ms: 0,
        now: "2026-08-21T10:00:00.000Z"
      )

    {:ok, _run} =
      PresentationTiming.finish(run,
        now_ms: 1_000,
        now: "2026-08-21T10:00:01.000Z"
      )

    assert [_run] = PresentationTiming.list_runs(metadata_dir, deck())

    other_deck = %{deck() | title: "Another talk"}
    assert PresentationTiming.list_runs(metadata_dir, other_deck) == []
  end

  defp deck do
    %Deck{
      title: "Timing Test",
      slides: [
        %Slide{id: :intro, title: "Intro"},
        %Slide{id: :middle, title: "Middle"},
        %Slide{id: :outro, title: "Outro"}
      ]
    }
  end
end
