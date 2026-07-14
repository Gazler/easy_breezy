defmodule EasyBreezy.Media.Supervisor do
  @moduledoc false

  use Supervisor

  alias EasyBreezy.Media.Cache

  def start_link(options \\ []) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(options) do
    children = [
      {Task.Supervisor, name: EasyBreezy.Media.TaskSupervisor},
      {Cache, Keyword.get(options, :cache, [])}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
