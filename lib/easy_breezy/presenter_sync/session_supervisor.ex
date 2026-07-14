defmodule EasyBreezy.PresenterSync.SessionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias EasyBreezy.PresenterSync.Session

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_session(name, producer) when is_pid(producer) do
    DynamicSupervisor.start_child(__MODULE__, {Session, name: name, producer: producer})
  catch
    :exit, {:noproc, _reason} -> {:error, :not_started}
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
