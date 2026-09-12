defmodule EasyBreezy.Media.Cache do
  @moduledoc false

  use GenServer

  @table __MODULE__.Table
  @default_max_entries 256
  @default_max_bytes 64 * 1024 * 1024

  def start_link(_options) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc false
  def fetch(key, loader) when is_function(loader, 0) do
    case lookup(key) do
      {:ok, value} -> value
      :error -> load_and_store(key, loader)
    end
  end

  @doc false
  def clear, do: call(:clear, :ok)

  @doc false
  def stats, do: call(:stats, %{entries: 0, bytes: 0})

  @doc false
  def table_name, do: @table

  @impl true
  def init(nil) do
    table =
      :ets.new(@table, [
        :named_table,
        :protected,
        :set,
        read_concurrency: true
      ])

    {:ok,
     %{
       table: table,
       max_entries: @default_max_entries,
       max_bytes: @default_max_bytes,
       entries: 0,
       bytes: 0
     }}
  end

  @impl true
  def handle_call({:store, key, result, size}, _from, state) do
    case lookup_table(state.table, key) do
      {:ok, cached} ->
        {:reply, cached, state}

      :error ->
        state = maybe_store(key, result, size, state)
        {:reply, result, state}
    end
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, %{state | entries: 0, bytes: 0}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, Map.take(state, [:entries, :bytes]), state}
  end

  defp load_and_store(key, loader) do
    result = loader.()

    case result do
      {:ok, _value} -> call({:store, key, result, estimated_size({key, result})}, result)
      _other -> result
    end
  end

  defp maybe_store(key, result, size, state) when size <= state.max_bytes do
    state
    |> evict_until_room(size)
    |> insert(key, result, size)
  end

  defp maybe_store(_key, _result, _size, state), do: state

  defp evict_until_room(state, incoming_size) do
    if state.entries >= state.max_entries or state.bytes + incoming_size > state.max_bytes do
      state |> evict_entry() |> evict_until_room(incoming_size)
    else
      state
    end
  end

  defp evict_entry(state) do
    case :ets.first(state.table) do
      key when key != :"$end_of_table" ->
        case :ets.take(state.table, key) do
          [{^key, _value, size}] ->
            %{state | entries: state.entries - 1, bytes: state.bytes - size}

          _missing ->
            state
        end

      :"$end_of_table" ->
        %{state | entries: 0, bytes: 0}
    end
  end

  defp insert(state, key, value, size) do
    true = :ets.insert(state.table, {key, value, size})

    %{
      state
      | entries: state.entries + 1,
        bytes: state.bytes + size
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
      [{^key, value, _size}] -> {:ok, value}
      _missing -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp call(request, fallback) do
    case Process.whereis(__MODULE__) do
      nil -> fallback
      cache -> GenServer.call(cache, request)
    end
  catch
    :exit, _reason -> fallback
  end

  defp estimated_size(value) do
    :erlang.external_size(value)
  rescue
    _error -> :uncacheable
  end
end
