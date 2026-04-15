defmodule EasyBreezy.PresenterClock do
  @moduledoc false

  use Breeze.View

  @tick_ms 1_000

  def mount(opts, term) do
    started_at_ms = Keyword.fetch!(opts, :started_at_ms)
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, assign(term, started_at_ms: started_at_ms, elapsed_label: elapsed_label(started_at_ms))}
  end

  def render(assigns) do
    ~H"""
    <box class="bg-panel text">{@elapsed_label}</box>
    """
  end

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, assign(term, elapsed_label: elapsed_label(term.assigns.started_at_ms))}
  end

  def handle_info(_, term), do: {:noreply, term}

  defp elapsed_label(started_at_ms) do
    total_seconds = div(System.monotonic_time(:millisecond) - started_at_ms, 1_000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "Elapsed #{pad2(minutes)}:#{pad2(seconds)}"
  end

  defp pad2(int) when int < 10, do: "0#{int}"
  defp pad2(int), do: Integer.to_string(int)
end
