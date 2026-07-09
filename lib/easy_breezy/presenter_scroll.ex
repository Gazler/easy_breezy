defmodule EasyBreezy.PresenterScroll do
  @moduledoc false

  alias Breeze.Implicit.Scroll
  alias Breeze.RenderState

  @keys ["ArrowDown", "ArrowUp", "j", "k"]
  @event_keys ["key", "ctrlKey", "altKey", "metaKey", "shiftKey"]

  def keys, do: @keys

  def export(term) do
    term.implicit_state
    |> Enum.reduce(%{}, fn
      {id, {Scroll, state}}, acc when is_binary(id) and is_map(state) ->
        Map.put(acc, id, Map.take(state, [:offset_y, :autoscroll, :pinned_bottom]))

      _other, acc ->
        acc
    end)
  end

  def import(term, nil), do: term

  def import(term, scroll_state) when is_map(scroll_state) do
    Enum.reduce(scroll_state, term, fn
      {id, state}, acc when is_binary(id) and is_map(state) ->
        RenderState.put_implicit_state(acc, id, Scroll, normalize_state(state))

      _other, acc ->
        acc
    end)
  end

  def import(term, _scroll_state), do: term

  def event(%{"key" => key} = event) when key in @keys do
    Map.take(event, @event_keys)
  end

  def event(_event), do: nil

  def apply(term, nil), do: term

  def apply(term, %{"key" => key} = event) when key in @keys do
    Enum.reduce(term.implicit_state, term, fn
      {id, {Scroll, state}}, acc ->
        apply_scroll_event(acc, id, state, event)

      _other, acc ->
        acc
    end)
  end

  def apply(term, _event), do: term

  defp apply_scroll_event(term, id, state, event) do
    element = Map.get(term.elements, id)
    payload = Map.put(event, "element", element)

    {:noreply, next_state} = Scroll.handle_event(:ignore_me, payload, state)
    RenderState.put_implicit_state(term, id, Scroll, next_state)
  end

  defp normalize_state(state) do
    %{
      offset_y: integer(Map.get(state, :offset_y) || Map.get(state, "offset_y")),
      autoscroll: Map.get(state, :autoscroll) || Map.get(state, "autoscroll"),
      pinned_bottom: boolean(Map.get(state, :pinned_bottom) || Map.get(state, "pinned_bottom"))
    }
  end

  defp integer(value) when is_integer(value) and value > 0, do: value
  defp integer(_value), do: 0

  defp boolean(value) when value in [true, false], do: value
  defp boolean(_value), do: false
end
