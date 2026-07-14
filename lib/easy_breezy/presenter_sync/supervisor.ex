defmodule EasyBreezy.PresenterSync.Supervisor do
  @moduledoc false

  use Supervisor

  alias EasyBreezy.PresenterSync.{Scope, SessionSupervisor}

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [Scope, SessionSupervisor]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
