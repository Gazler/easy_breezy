defmodule EasyBreezy.PresenterSync.Scope do
  @moduledoc false

  @scope __MODULE__

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {:pg, :start_link, [@scope]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  def name, do: @scope

  def started?, do: is_pid(Process.whereis(@scope))
end
