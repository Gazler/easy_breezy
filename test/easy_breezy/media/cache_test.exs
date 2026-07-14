defmodule EasyBreezy.Media.CacheTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.Media.Cache

  setup do
    assert Process.whereis(EasyBreezy.Media.Supervisor)
    assert :ok = Cache.clear()
    :ok
  end

  test "the supervised cache owns a protected ETS table" do
    table = Cache.table_name()

    assert :ets.info(table, :owner) == Process.whereis(Cache)
    assert :ets.info(table, :protection) == :protected

    caller =
      spawn(fn ->
        assert Cache.fetch(:ownership, fn -> {:ok, :value} end) == {:ok, :value}
      end)

    monitor = Process.monitor(caller)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}

    assert :ets.info(table, :owner) == Process.whereis(Cache)

    assert Cache.fetch(:ownership, fn -> flunk("cached value was not retained") end) ==
             {:ok, :value}
  end

  test "concurrent misses run one loader" do
    counter = :counters.new(1, [:atomics])

    tasks =
      for _index <- 1..20 do
        Task.async(fn ->
          Cache.fetch(:single_flight, fn ->
            :counters.add(counter, 1, 1)
            Process.sleep(25)
            {:ok, :loaded}
          end)
        end)
      end

    assert Enum.map(tasks, &Task.await/1) == List.duplicate({:ok, :loaded}, 20)
    assert :counters.get(counter, 1) == 1
  end

  test "failed loads remain retryable" do
    counter = :counters.new(1, [:atomics])

    loader = fn ->
      :counters.add(counter, 1, 1)
      {:error, :unavailable}
    end

    assert Cache.fetch(:retryable, loader) == {:error, :unavailable}
    assert Cache.fetch(:retryable, loader) == {:error, :unavailable}
    assert :counters.get(counter, 1) == 2
    assert Cache.stats().entries == 0
  end

  test "the cache enforces its entry bound" do
    for index <- 1..300 do
      assert Cache.fetch({:bounded, index}, fn -> {:ok, index} end) == {:ok, index}
    end

    assert %{entries: 256, bytes: bytes} = Cache.stats()
    assert bytes > 0

    assert Cache.fetch({:bounded, 300}, fn -> flunk("newest entry was evicted") end) ==
             {:ok, 300}
  end

  test "one-for-all restarts both the cache and its task supervisor" do
    cache = Process.whereis(Cache)
    task_supervisor = Process.whereis(EasyBreezy.Media.TaskSupervisor)
    table = Cache.table_name()

    Process.exit(cache, :kill)

    assert eventually(fn ->
             new_cache = Process.whereis(Cache)
             new_task_supervisor = Process.whereis(EasyBreezy.Media.TaskSupervisor)

             is_pid(new_cache) and new_cache != cache and is_pid(new_task_supervisor) and
               new_task_supervisor != task_supervisor and :ets.info(table, :owner) == new_cache
           end)
  end

  defp eventually(assertion, attempts \\ 50)

  defp eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      true
    else
      Process.sleep(10)
      eventually(assertion, attempts - 1)
    end
  end

  defp eventually(_assertion, 0), do: false
end
