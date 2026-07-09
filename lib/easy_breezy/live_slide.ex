defmodule EasyBreezy.LiveSlide do
  @moduledoc false

  def live?(%{layout: :breeze}), do: true
  def live?(_slide), do: false

  def sync?(%{layout: :breeze, payload: payload}) do
    payload = normalize_payload(payload)

    Map.get(payload, :sync_live_state, Map.get(payload, "sync_live_state", true)) != false
  end

  def sync?(_slide), do: false

  def synced_ids(%{slides: slides}) when is_list(slides) do
    slides
    |> Enum.filter(&sync?/1)
    |> Enum.map(&id/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  def synced_ids(_deck), do: MapSet.new()

  def sync_id?(deck, live_id) when is_binary(live_id) do
    deck
    |> synced_ids()
    |> MapSet.member?(live_id)
  end

  def sync_id?(_deck, _live_id), do: false

  def id(%{layout: :breeze, id: slide_id, payload: payload}) do
    payload = normalize_payload(payload)

    Map.get(payload, :live_id) ||
      Map.get(payload, "live_id") ||
      live_id_for(slide_id || Map.get(payload, :view) || Map.get(payload, "view"))
  end

  def id(_slide), do: nil

  def live_id_for(nil), do: nil

  def live_id_for(value) do
    "breeze-slide-" <>
      (value
       |> to_string()
       |> String.replace(".", "-"))
  end

  def focus(term, %{layout: :breeze} = slide) do
    case id(slide) do
      id when is_binary(id) ->
        if sync?(slide) do
          Breeze.View.focus(term, id)
        else
          maybe_clear_focus(term, id)
        end

      _other ->
        term
    end
  end

  def focus(term, _slide), do: Breeze.View.focus(term, nil)

  defp maybe_clear_focus(%{focused: focused} = term, id) when is_binary(focused) do
    if focused == id or String.starts_with?(focused, id <> "::") do
      Breeze.View.focus(term, nil)
    else
      term
    end
  end

  defp maybe_clear_focus(term, _id), do: term

  defp normalize_payload(payload) when is_atom(payload), do: %{view: payload}
  defp normalize_payload(payload) when is_map(payload), do: payload
  defp normalize_payload(_payload), do: %{}
end
