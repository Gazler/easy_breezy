defmodule EasyBreezy.Layouts.BreezeSlide do
  @moduledoc false

  use Breeze.View

  attr :slide_id, :any, required: true
  attr :view, :atom, required: true
  attr :live_id, :string, default: nil
  attr :start_opts, :list, default: []
  attr :assigns, :map, default: %{}
  attr :class, :string, default: "width-full height-full"
  attr :style, :any, default: nil
  attr :focusable, :boolean, default: true

  def breeze_slide(assigns) do
    assigns =
      Map.merge(assigns, %{
        live_id:
          Map.get(assigns, :live_id) ||
            live_id_for(Map.fetch!(assigns, :slide_id) || Map.fetch!(assigns, :view)),
        child_assigns: Map.get(assigns, :assigns, %{}),
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

  defp live_id_for(value) do
    "breeze-slide-" <>
      (value
       |> to_string()
       |> String.replace(".", "-"))
  end
end
