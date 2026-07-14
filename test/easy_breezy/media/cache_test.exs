defmodule EasyBreezy.Media.CacheTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.Media.Cache

  setup do
    assert Process.whereis(Cache)
    assert :ok = Cache.clear()
    :ok
  end

  test "the application cache owns a protected ETS table" do
    table = Cache.table_name()

    assert :ets.info(table, :owner) == Process.whereis(Cache)
    assert :ets.info(table, :protection) == :protected

    caller = spawn(fn -> Cache.fetch(:ownership, fn -> {:ok, :value} end) end)
    monitor = Process.monitor(caller)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}

    assert :ets.info(table, :owner) == Process.whereis(Cache)

    assert Cache.fetch(:ownership, fn -> flunk("cached value was not retained") end) ==
             {:ok, :value}
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

  test "the cache evicts entries at the entry bound" do
    for index <- 1..300 do
      assert Cache.fetch({:bounded, index}, fn -> {:ok, index} end) == {:ok, index}
    end

    assert %{entries: 256, bytes: bytes} = Cache.stats()
    assert bytes > 0

    assert Cache.fetch({:bounded, 300}, fn -> flunk("newest entry was evicted") end) ==
             {:ok, 300}
  end

  test "the application supervisor restarts the cache" do
    cache = Process.whereis(Cache)
    table = Cache.table_name()

    Process.exit(cache, :kill)

    assert eventually(fn ->
             new_cache = Process.whereis(Cache)
             is_pid(new_cache) and new_cache != cache and :ets.info(table, :owner) == new_cache
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
