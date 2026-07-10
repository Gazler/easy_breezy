defmodule EasyBreezy.PresenterClock do
  @moduledoc false

  use Breeze.View

  alias EasyBreezy.ElapsedTime

  @tick_ms 1_000

  def mount(opts, term) do
    started_at_ms = Keyword.fetch!(opts, :started_at_ms)
    Process.send_after(self(), :tick, @tick_ms)

    {:ok,
     assign(term, started_at_ms: started_at_ms, elapsed_label: ElapsedTime.label(started_at_ms))}
  end

  def render(assigns) do
    ~H"""
    <box class="bg-panel text">{@elapsed_label}</box>
    """
  end

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, assign(term, elapsed_label: ElapsedTime.label(term.assigns.started_at_ms))}
  end

  def handle_info(_, term), do: {:noreply, term}
end
