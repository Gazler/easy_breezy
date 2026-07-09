defmodule EasyBreezy.Layouts.BreezeSlide do
  @moduledoc false

  use Breeze.View

  attr :slide_id, :any, required: true
  attr :view, :atom, required: true
  attr :live_id, :string, default: nil
  attr :start_opts, :list, default: []
  attr :assigns, :map, default: %{}
  attr :live_state, :map, default: %{}
  attr :class, :string, default: "width-full height-full"
  attr :style, :any, default: nil
  attr :focusable, :boolean, default: true

  def breeze_slide(assigns) do
    live_id =
      Map.get(assigns, :live_id) ||
        EasyBreezy.LiveSlide.live_id_for(
          Map.fetch!(assigns, :slide_id) || Map.fetch!(assigns, :view)
        )

    assigns =
      Map.merge(assigns, %{
        live_id: live_id,
        child_assigns:
          Map.merge(
            Map.get(assigns, :assigns, %{}),
            live_state_assigns(Map.get(assigns, :live_state, %{}), live_id)
          ),
        start_opts: Map.get(assigns, :start_opts, []),
        class: Map.get(assigns, :class, "width-full height-full"),
        style: Map.get(assigns, :style),
        focusable: Map.get(assigns, :focusable, true)
      })

    ~H"""
    <box class="width-full height-full">
      <live
        id={@live_id}
        view={@view}
        start_opts={@start_opts}
        assigns={@child_assigns}
        class={@class}
        style={@style}
        focusable={@focusable}
      >
      </live>
    </box>
    """
  end

  defp live_state_assigns(live_state, live_id) when is_map(live_state) do
    case Map.get(live_state, live_id) || Map.get(live_state, to_string(live_id)) do
      %{assigns: assigns} when is_map(assigns) -> assigns
      %{"assigns" => assigns} when is_map(assigns) -> assigns
      assigns when is_map(assigns) -> assigns
      _other -> %{}
    end
  end

  defp live_state_assigns(_live_state, _live_id), do: %{}
end
