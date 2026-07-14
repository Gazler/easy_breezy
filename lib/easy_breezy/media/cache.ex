defmodule EasyBreezy.Media.Cache do
  @moduledoc false

  use GenServer

  @table __MODULE__.Table
  @task_supervisor EasyBreezy.Media.TaskSupervisor
  @default_max_entries 256
  @default_max_bytes 64 * 1024 * 1024

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc false
  def fetch(key, loader) when is_function(loader, 0) do
    case lookup(key) do
      {:ok, value} ->
        value

      :error ->
        fetch_miss(key, loader)
    end
  end

  @doc false
  def clear do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :clear)
    else
      :ok
    end
  end

  @doc false
  def stats do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :stats)
    else
      %{entries: 0, bytes: 0, in_flight: 0}
    end
  end

  @doc false
  def table_name, do: @table

  @impl true
  def init(options) do
    configured = Application.get_env(:easy_breezy, __MODULE__, [])
    options = Keyword.merge(configured, options)

    table =
      :ets.new(@table, [
        :named_table,
        :protected,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok,
     %{
       table: table,
       max_entries: positive_option(options, :max_entries, @default_max_entries),
       max_bytes: positive_option(options, :max_bytes, @default_max_bytes),
       entries: 0,
       bytes: 0,
       sequence: 0,
       insertion_order: :gb_trees.empty(),
       in_flight: %{},
       tasks: %{}
     }}
  end

  @impl true
  def handle_call({:fetch, key, loader}, from, state) do
    case lookup_table(state.table, key) do
      {:ok, value} ->
        {:reply, value, state}

      :error ->
        coordinate_miss(key, loader, from, state)
    end
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.table)

    {:reply, :ok,
     %{
       state
       | entries: 0,
         bytes: 0,
         sequence: 0,
         insertion_order: :gb_trees.empty()
     }}
  end

  def handle_call(:stats, _from, state) do
    stats = %{entries: state.entries, bytes: state.bytes, in_flight: map_size(state.in_flight)}
    {:reply, stats, state}
  end

  @impl true
  def handle_info({reference, {result, size}}, state)
      when is_reference(reference) and is_integer(size) do
    case Map.pop(state.tasks, reference) do
      {nil, _tasks} ->
        {:noreply, state}

      {key, tasks} ->
        Process.demonitor(reference, [:flush])
        {flight, in_flight} = Map.pop!(state.in_flight, key)

        state = %{state | tasks: tasks, in_flight: in_flight}
        state = maybe_store(key, result, size, state)
        Enum.each(flight.waiters, &GenServer.reply(&1, result))

        {:noreply, state}
    end
  end

  def handle_info({:DOWN, reference, :process, _pid, reason}, state) do
    case Map.pop(state.tasks, reference) do
      {nil, _tasks} ->
        {:noreply, state}

      {key, tasks} ->
        {flight, in_flight} = Map.pop!(state.in_flight, key)
        result = {:error, {:media_task_failed, reason}}
        Enum.each(flight.waiters, &GenServer.reply(&1, result))

        {:noreply, %{state | tasks: tasks, in_flight: in_flight}}
    end
  end

  defp fetch_miss(key, loader) do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :media_runtime_unavailable}

      cache ->
        try do
          GenServer.call(cache, {:fetch, key, loader}, :infinity)
        catch
          :exit, _reason -> {:error, :media_runtime_unavailable}
        end
    end
  end

  defp coordinate_miss(key, loader, from, state) do
    case state.in_flight do
      %{^key => flight} ->
        flight = %{flight | waiters: [from | flight.waiters]}
        {:noreply, put_in(state.in_flight[key], flight)}

      _other ->
        task =
          Task.Supervisor.async_nolink(@task_supervisor, fn ->
            result = loader.()
            {result, result_size(key, result)}
          end)

        flight = %{task: task, waiters: [from]}

        {:noreply,
         %{
           state
           | in_flight: Map.put(state.in_flight, key, flight),
             tasks: Map.put(state.tasks, task.ref, key)
         }}
    end
  end

  # Only successful tagged results are retained. Errors remain retryable instead of
  # poisoning the cache indefinitely.
  defp maybe_store(key, {:ok, _value} = result, size, state) do
    if size <= state.max_bytes and state.max_entries > 0 do
      state
      |> evict_until_room(size)
      |> insert(key, result, size)
    else
      state
    end
  end

  defp maybe_store(_key, _result, _size, state), do: state

  defp evict_until_room(state, incoming_size) do
    if state.entries >= state.max_entries or state.bytes + incoming_size > state.max_bytes do
      state |> evict_oldest() |> evict_until_room(incoming_size)
    else
      state
    end
  end

  defp evict_oldest(%{entries: 0} = state), do: state

  defp evict_oldest(state) do
    {sequence, key, insertion_order} = :gb_trees.take_smallest(state.insertion_order)

    case :ets.take(state.table, key) do
      [{^key, _value, size, ^sequence}] ->
        %{
          state
          | entries: state.entries - 1,
            bytes: state.bytes - size,
            insertion_order: insertion_order
        }

      _missing ->
        %{state | insertion_order: insertion_order}
    end
  end

  defp insert(state, key, value, size) do
    sequence = state.sequence + 1
    true = :ets.insert(state.table, {key, value, size, sequence})

    %{
      state
      | entries: state.entries + 1,
        bytes: state.bytes + size,
        sequence: sequence,
        insertion_order: :gb_trees.insert(sequence, key, state.insertion_order)
    }
  end

  defp lookup(key) do
    case :ets.whereis(@table) do
      :undefined -> :error
      table -> lookup_table(table, key)
    end
  rescue
    ArgumentError -> :error
  end

  defp lookup_table(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value, _size, _sequence}] -> {:ok, value}
      _missing -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp result_size(key, {:ok, _value} = result), do: estimated_size({key, result})
  defp result_size(_key, _result), do: 0

  defp estimated_size(value) do
    :erlang.external_size(value)
  rescue
    _error -> :erts_debug.flat_size(value) * :erlang.system_info(:wordsize)
  end

  defp positive_option(options, key, default) do
    case Keyword.get(options, key, default) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end
end
