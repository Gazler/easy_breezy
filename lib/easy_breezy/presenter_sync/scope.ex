defmodule EasyBreezy.PresenterSync.Scope do
  @moduledoc false

  @scope __MODULE__

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {:pg, :start_link, [@scope]},
      type: :worker
    }
  end

  def name, do: @scope
end
