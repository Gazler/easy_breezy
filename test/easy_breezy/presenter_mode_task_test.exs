defmodule EasyBreezy.PresenterModeTaskTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.MixTask.PresenterMode

  defmodule RunningEpmd do
    def names, do: {:ok, []}
  end

  defmodule MissingEpmd do
    def names, do: {:error, :address}
  end

  defmodule RecordingNode do
    def start(name, options) do
      send(self(), {:node_start, name, options})
      {:ok, self()}
    end
  end

  defmodule FailingNode do
    def start(_name, _options), do: {:error, :name_in_use}
  end

  test "requires mix run arguments instead of assuming a slideshow filename" do
    error =
      assert_raise Mix.Error, fn ->
        PresenterMode.run_args!(:slides, [])
      end

    assert error.message =~ "mix easy_breezy.slides slides.exs"

    assert PresenterMode.run_args!(:slides, ["--no-compile", "talks/demo.exs", "guest"]) == [
             "--no-compile",
             "talks/demo.exs",
             "guest"
           ]
  end

  test "uses stable loopback node names for the slides and presenter views" do
    assert PresenterMode.node_name(:slides) == :"slides@127.0.0.1"
    assert PresenterMode.node_name(:presenter) == :"presenter@127.0.0.1"
  end

  test "requires epmd to already be running" do
    assert :ok = PresenterMode.ensure_epmd!(:slides, RunningEpmd)

    error =
      assert_raise Mix.Error, ~r/easy_breezy\.slides requires epmd/, fn ->
        PresenterMode.ensure_epmd!(:slides, MissingEpmd)
      end

    assert error.message =~ "epmd -daemon"
    assert error.message =~ "EPMD check failed with: :address"
  end

  test "starts both views with long names" do
    assert :ok = PresenterMode.start_distribution!(:slides, RecordingNode)

    assert_receive {:node_start, :"slides@127.0.0.1", [name_domain: :longnames]}

    assert :ok = PresenterMode.start_distribution!(:presenter, RecordingNode)

    assert_receive {:node_start, :"presenter@127.0.0.1", [name_domain: :longnames]}
  end

  test "reports distribution startup errors" do
    assert_raise Mix.Error, ~r/using long names: :name_in_use/, fn ->
      PresenterMode.start_distribution!(:presenter, FailingNode)
    end
  end
end
