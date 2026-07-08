defmodule Counter do
  use Breeze.View

  def mount(_opts, term) do
    {:ok, assign(term, count: 0)}
  end

  def render(assigns) do
    ~H"""
    <box class="width-full height-full bg">
      <box class="bold text-1">Counter</box>
      <box>value: {@count}</box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term) do
    {:noreply, assign(term, count: term.assigns.count + 1)}
  end

  def handle_event(_, %{"key" => "ArrowDown"}, term) do
    {:noreply, assign(term, count: term.assigns.count - 1)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
