defmodule EasyBreezy.Slide do
  @moduledoc false

  defstruct [
    :id,
    :title,
    :layout,
    :source,
    :source_range,
    :payload,
    steps: 0,
    transition: :slide,
    disable_transitions?: false
  ]

  def resolve_payload(%{payload: payload}, body_width, step) when is_function(payload, 2),
    do: payload.(body_width, step)

  def resolve_payload(%{layout: :breeze, payload: view}, _body_width, _step)
      when is_atom(view),
      do: %{view: view}

  def resolve_payload(%{payload: payload}, _body_width, _step) when is_map(payload),
    do: payload

  def resolve_payload(_slide, _body_width, _step), do: %{}
end
