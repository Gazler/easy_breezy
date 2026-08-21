defmodule EasyBreezy.PresentationTiming do
  @moduledoc false

  alias EasyBreezy.ElapsedTime

  @version 1
  @metadata_directory ".easy_breezy"
  @timings_directory "timings"
  @timing_file_pattern "*.json"

  defmodule Run do
    @moduledoc false

    defstruct [
      :id,
      :path,
      :deck,
      :started_at,
      :ended_at,
      :tracked_slide_index,
      :segment_started_at_ms,
      :backtracking_started_at_ms,
      :backtracking_started_at,
      accumulated_ms: 0,
      status: :active,
      visits: []
    ]
  end

  def metadata_dir(base_dir \\ File.cwd!()) when is_binary(base_dir) do
    Path.join(base_dir, @metadata_directory)
  end

  def timings_dir(metadata_dir) when is_binary(metadata_dir) do
    Path.join(metadata_dir, @timings_directory)
  end

  def start_run(deck, slide_index, metadata_dir \\ nil, opts \\ []) do
    metadata_dir = metadata_dir || metadata_dir()
    {now_ms, now} = current_time(opts)

    case slide_info(deck, slide_index) do
      nil ->
        {:error, :invalid_slide_index}

      slide ->
        id = run_id(now)
        path = Path.join(timings_dir(metadata_dir), "#{id}.json")

        run = %Run{
          id: id,
          path: path,
          deck: deck_descriptor(deck),
          started_at: now,
          tracked_slide_index: slide_index,
          segment_started_at_ms: now_ms,
          visits: [new_visit(slide, now)]
        }

        persist(run)
    end
  end

  def observe_slide(run, deck, slide_index, opts \\ [])

  def observe_slide(%Run{status: :active} = run, deck, slide_index, opts) do
    {now_ms, now} = current_time(opts)

    case slide_info(deck, slide_index) do
      nil ->
        {:error, :invalid_slide_index, run}

      slide ->
        observe_valid_slide(run, slide, slide_index, now_ms, now)
    end
  end

  def observe_slide(%Run{} = run, _deck, _slide_index, _opts),
    do: {:error, :completed_run, run}

  def finish(run, opts \\ [])

  def finish(%Run{status: :complete} = run, _opts), do: {:ok, run}

  def finish(%Run{status: :active} = run, opts) do
    {now_ms, now} = current_time(opts)

    run
    |> close_current_visit(now_ms, now)
    |> Map.replace!(:status, :complete)
    |> Map.replace!(:ended_at, now)
    |> persist()
  end

  def list_runs(metadata_dir, deck \\ nil) when is_binary(metadata_dir) do
    directory = timings_dir(metadata_dir)

    directory
    |> Path.join(@timing_file_pattern)
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case load_run(path) do
        {:ok, run} -> [run]
        {:error, _reason} -> []
      end
    end)
    |> Enum.uniq_by(& &1.id)
    |> maybe_filter_deck(deck)
    |> Enum.sort_by(& &1.started_at, :desc)
  end

  def compatible?(%Run{deck: stored}, deck) do
    current = deck_descriptor(deck)

    case {Map.get(stored, :source_path), Map.get(current, :source_path)} do
      {stored_path, current_path} when is_binary(stored_path) and is_binary(current_path) ->
        stored_path == current_path

      _paths ->
        Map.get(stored, :title) == Map.get(current, :title) and
          slide_ids(stored) == slide_ids(current)
    end
  end

  def complete?(%Run{status: :complete}), do: true
  def complete?(%Run{}), do: false

  def backtracking?(%Run{backtracking_started_at_ms: value}), do: is_integer(value)

  def current_duration_ms(run, now_ms \\ System.monotonic_time(:millisecond))

  def current_duration_ms(%Run{status: :active} = run, now_ms) when is_integer(now_ms) do
    if backtracking?(run) do
      run.accumulated_ms
    else
      run.accumulated_ms + elapsed_ms(run.segment_started_at_ms, now_ms)
    end
  end

  def current_duration_ms(%Run{}, _now_ms), do: 0

  def expected_duration_ms(%Run{} = run, slide_index, slide_id \\ nil)
      when is_integer(slide_index) do
    slide_id = normalize_id(slide_id)

    durations =
      run.visits
      |> Enum.filter(fn visit ->
        if is_binary(slide_id) do
          Map.get(visit, :slide_id) == slide_id
        else
          Map.get(visit, :slide_index) == slide_index
        end
      end)
      |> Enum.map(&Map.get(&1, :duration_ms))
      |> Enum.filter(&is_integer/1)

    case durations do
      [] -> nil
      durations -> Enum.sum(durations)
    end
  end

  def total_duration_ms(%Run{} = run) do
    run.visits
    |> Enum.map(&Map.get(&1, :duration_ms))
    |> Enum.filter(&is_integer/1)
    |> Enum.sum()
  end

  def visited_slide_count(%Run{} = run) do
    run.visits
    |> Enum.filter(&is_integer(Map.get(&1, :duration_ms)))
    |> Enum.map(&Map.get(&1, :slide_index))
    |> Enum.uniq()
    |> length()
  end

  def format_duration(elapsed_ms) when is_integer(elapsed_ms) do
    elapsed_ms
    |> ElapsedTime.label_from_elapsed("")
    |> String.trim_leading()
  end

  def format_duration(_elapsed_ms), do: "--:--"

  defp observe_valid_slide(run, _slide, slide_index, _now_ms, _now)
       when slide_index < run.tracked_slide_index and
              is_integer(run.backtracking_started_at_ms),
       do: {:ok, run}

  defp observe_valid_slide(run, _slide, slide_index, now_ms, now)
       when slide_index < run.tracked_slide_index do
    run = %{
      run
      | accumulated_ms: run.accumulated_ms + elapsed_ms(run.segment_started_at_ms, now_ms),
        segment_started_at_ms: nil,
        backtracking_started_at_ms: now_ms,
        backtracking_started_at: now
    }

    {:ok, run}
  end

  defp observe_valid_slide(run, _slide, slide_index, now_ms, _now)
       when slide_index == run.tracked_slide_index and
              is_integer(run.backtracking_started_at_ms) do
    {:ok,
     %{
       run
       | segment_started_at_ms: now_ms,
         backtracking_started_at_ms: nil,
         backtracking_started_at: nil
     }}
  end

  defp observe_valid_slide(run, _slide, slide_index, _now_ms, _now)
       when slide_index == run.tracked_slide_index,
       do: {:ok, run}

  defp observe_valid_slide(run, slide, slide_index, now_ms, now)
       when slide_index > run.tracked_slide_index do
    run =
      run
      |> close_current_visit(now_ms, now)
      |> Map.replace!(:tracked_slide_index, slide_index)
      |> Map.replace!(:segment_started_at_ms, now_ms)
      |> Map.replace!(:backtracking_started_at_ms, nil)
      |> Map.replace!(:backtracking_started_at, nil)
      |> Map.replace!(:accumulated_ms, 0)
      |> Map.update!(:visits, &(&1 ++ [new_visit(slide, now)]))

    persist(run)
  end

  defp close_current_visit(%Run{visits: []} = run, _now_ms, _now), do: run

  defp close_current_visit(%Run{} = run, now_ms, now) do
    {duration_ms, left_at} =
      if backtracking?(run) do
        {run.accumulated_ms, run.backtracking_started_at}
      else
        {run.accumulated_ms + elapsed_ms(run.segment_started_at_ms, now_ms), now}
      end

    visits =
      List.update_at(run.visits, -1, fn visit ->
        if is_nil(Map.get(visit, :duration_ms)) do
          %{visit | left_at: left_at, duration_ms: duration_ms}
        else
          visit
        end
      end)

    %{run | visits: visits}
  end

  defp elapsed_ms(started_at_ms, now_ms)
       when is_integer(started_at_ms) and is_integer(now_ms),
       do: max(now_ms - started_at_ms, 0)

  defp elapsed_ms(_started_at_ms, _now_ms), do: 0

  defp new_visit(slide, entered_at) do
    %{
      slide_index: slide.index,
      slide_id: slide.id,
      title: slide.title,
      entered_at: entered_at,
      left_at: nil,
      duration_ms: nil
    }
  end

  defp slide_info(%{slides: slides}, slide_index)
       when is_list(slides) and is_integer(slide_index) and slide_index >= 0 do
    case Enum.at(slides, slide_index) do
      nil ->
        nil

      slide ->
        %{index: slide_index, id: normalize_id(Map.get(slide, :id)), title: slide_title(slide)}
    end
  end

  defp slide_info(_deck, _slide_index), do: nil

  defp deck_descriptor(deck) do
    slides =
      deck
      |> Map.get(:slides, [])
      |> Enum.with_index()
      |> Enum.map(fn {slide, index} ->
        %{index: index, id: normalize_id(Map.get(slide, :id)), title: slide_title(slide)}
      end)

    %{
      title: deck |> Map.get(:title, "Untitled Deck") |> to_string(),
      source_path: normalize_source_path(Map.get(deck, :source_path)),
      slides: slides
    }
  end

  defp slide_title(slide), do: slide |> Map.get(:title, "Untitled Slide") |> to_string()

  defp normalize_id(nil), do: nil
  defp normalize_id(id) when is_binary(id), do: id
  defp normalize_id(id) when is_atom(id) or is_integer(id), do: to_string(id)
  defp normalize_id(id), do: inspect(id)

  defp normalize_source_path(path) when is_binary(path), do: Path.expand(path)
  defp normalize_source_path(_path), do: nil

  defp slide_ids(%{slides: slides}) when is_list(slides), do: Enum.map(slides, &Map.get(&1, :id))
  defp slide_ids(_descriptor), do: []

  defp maybe_filter_deck(runs, nil), do: runs
  defp maybe_filter_deck(runs, deck), do: Enum.filter(runs, &compatible?(&1, deck))

  defp current_time(opts) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.monotonic_time(:millisecond) end)
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() end)
    {now_ms, normalize_time(now)}
  end

  defp normalize_time(%DateTime{} = now),
    do: now |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()

  defp normalize_time(now) when is_binary(now), do: now

  defp run_id(now) do
    timestamp = String.replace(now, ~r/[^0-9]/, "")
    unique = System.unique_integer([:positive, :monotonic])
    "#{timestamp}-#{unique}"
  end

  defp persist(%Run{} = run) do
    directory = Path.dirname(run.path)
    temporary = "#{run.path}.tmp-#{System.unique_integer([:positive, :monotonic])}"

    result =
      with {:ok, contents} <- encode_json(run),
           :ok <- File.mkdir_p(directory),
           :ok <- File.write(temporary, contents),
           :ok <- File.rename(temporary, run.path) do
        :ok
      end

    case result do
      :ok ->
        {:ok, run}

      {:error, reason} ->
        File.rm(temporary)
        {:error, {:persist_failed, reason}, run}
    end
  end

  defp persisted_map(%Run{} = run) do
    %{
      version: @version,
      id: run.id,
      deck: run.deck,
      started_at: run.started_at,
      ended_at: run.ended_at,
      total_duration_ms: total_duration_ms(run),
      visits: run.visits,
      status: Atom.to_string(run.status)
    }
  end

  defp encode_json(%Run{} = run) do
    case Jason.encode(persisted_map(run), pretty: true) do
      {:ok, contents} -> {:ok, contents <> "\n"}
      {:error, reason} -> {:error, {:json_encode_failed, reason}}
    end
  end

  defp load_run(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, data} <- decode_json(contents),
         :ok <- validate(data) do
      {:ok,
       %Run{
         id: data.id,
         path: path,
         deck: data.deck,
         started_at: data.started_at,
         ended_at: data.ended_at,
         status: data.status,
         visits: data.visits
       }}
    end
  end

  defp decode_json(contents) do
    with {:ok, data} <- Jason.decode(contents),
         {:ok, data} <- normalize_json_data(data) do
      {:ok, data}
    else
      _error -> {:error, :invalid_timing_file}
    end
  end

  defp normalize_json_data(
         %{
           "version" => version,
           "id" => id,
           "deck" => deck,
           "started_at" => started_at,
           "status" => status,
           "visits" => visits
         } = data
       ) do
    with {:ok, status} <- normalize_json_status(status),
         {:ok, deck} <- normalize_json_deck(deck),
         {:ok, visits} <- normalize_json_list(visits, &normalize_json_visit/1) do
      {:ok,
       %{
         version: version,
         id: id,
         deck: deck,
         started_at: started_at,
         ended_at: Map.get(data, "ended_at"),
         status: status,
         total_duration_ms: Map.get(data, "total_duration_ms"),
         visits: visits
       }}
    end
  end

  defp normalize_json_data(_data), do: {:error, :invalid_timing_file}

  defp normalize_json_status("active"), do: {:ok, :active}
  defp normalize_json_status("complete"), do: {:ok, :complete}
  defp normalize_json_status(_status), do: {:error, :invalid_timing_file}

  defp normalize_json_deck(%{"title" => title, "slides" => slides} = deck)
       when is_binary(title) and is_list(slides) do
    source_path = Map.get(deck, "source_path")

    with true <- is_nil(source_path) or is_binary(source_path),
         {:ok, slides} <- normalize_json_list(slides, &normalize_json_slide/1) do
      {:ok, %{title: title, source_path: source_path, slides: slides}}
    else
      _error -> {:error, :invalid_timing_file}
    end
  end

  defp normalize_json_deck(_deck), do: {:error, :invalid_timing_file}

  defp normalize_json_slide(%{"index" => index, "id" => id, "title" => title})
       when is_integer(index) and index >= 0 and (is_nil(id) or is_binary(id)) and
              is_binary(title),
       do: {:ok, %{index: index, id: id, title: title}}

  defp normalize_json_slide(_slide), do: {:error, :invalid_timing_file}

  defp normalize_json_visit(
         %{
           "slide_index" => slide_index,
           "slide_id" => slide_id,
           "title" => title,
           "entered_at" => entered_at
         } = visit
       )
       when is_integer(slide_index) and slide_index >= 0 and
              (is_nil(slide_id) or is_binary(slide_id)) and is_binary(title) and
              is_binary(entered_at) do
    left_at = Map.get(visit, "left_at")
    duration_ms = Map.get(visit, "duration_ms")

    if (is_nil(left_at) or is_binary(left_at)) and
         (is_nil(duration_ms) or (is_integer(duration_ms) and duration_ms >= 0)) do
      {:ok,
       %{
         slide_index: slide_index,
         slide_id: slide_id,
         title: title,
         entered_at: entered_at,
         left_at: left_at,
         duration_ms: duration_ms
       }}
    else
      {:error, :invalid_timing_file}
    end
  end

  defp normalize_json_visit(_visit), do: {:error, :invalid_timing_file}

  defp normalize_json_list(values, normalizer) when is_list(values) do
    case Enum.reduce_while(values, [], fn value, normalized ->
           case normalizer.(value) do
             {:ok, value} -> {:cont, [value | normalized]}
             {:error, _reason} -> {:halt, :error}
           end
         end) do
      :error -> {:error, :invalid_timing_file}
      normalized -> {:ok, Enum.reverse(normalized)}
    end
  end

  defp normalize_json_list(_values, _normalizer), do: {:error, :invalid_timing_file}

  defp validate(
         %{
           version: @version,
           id: id,
           deck: deck,
           started_at: started_at,
           status: status,
           visits: visits
         } = data
       )
       when is_binary(id) and is_map(deck) and is_binary(started_at) and
              status in [:active, :complete] and is_list(visits) do
    ended_at = Map.get(data, :ended_at)

    if (is_nil(ended_at) or is_binary(ended_at)) and valid_deck?(deck) and
         Enum.all?(visits, &valid_visit?/1) do
      :ok
    else
      {:error, :invalid_timing_file}
    end
  end

  defp validate(_data), do: {:error, :invalid_timing_file}

  defp valid_deck?(%{title: title, source_path: source_path, slides: slides})
       when is_binary(title) and (is_nil(source_path) or is_binary(source_path)) and
              is_list(slides),
       do: Enum.all?(slides, &valid_slide?/1)

  defp valid_deck?(_deck), do: false

  defp valid_slide?(%{index: index, id: id, title: title}),
    do: is_integer(index) and index >= 0 and (is_nil(id) or is_binary(id)) and is_binary(title)

  defp valid_slide?(_slide), do: false

  defp valid_visit?(%{
         slide_index: slide_index,
         slide_id: slide_id,
         title: title,
         entered_at: entered_at,
         left_at: left_at,
         duration_ms: duration_ms
       }),
       do:
         is_integer(slide_index) and slide_index >= 0 and
           (is_nil(slide_id) or is_binary(slide_id)) and is_binary(title) and
           is_binary(entered_at) and (is_nil(left_at) or is_binary(left_at)) and
           (is_nil(duration_ms) or (is_integer(duration_ms) and duration_ms >= 0))

  defp valid_visit?(_visit), do: false
end
