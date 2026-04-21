defmodule EasyBreezy.Layouts.LiveSlide do
  @moduledoc false

  use Breeze.View

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:view, :any, default: nil)
  attr(:start_opts, :any, default: [])
  attr(:full_bleed, :boolean, default: false)
  attr(:persistent, :boolean, default: false)
  attr(:hosted_live, :boolean, default: false)
  attr(:body_width, :integer, required: true)
  attr(:body_height, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def live_slide(assigns) do
    full_bleed = truthy?(Map.get(assigns, :full_bleed, false))
    hosted_live = truthy?(Map.get(assigns, :hosted_live, false))
    persistent = truthy?(Map.get(assigns, :persistent, false))

    {panel_height, live_width, live_height} =
      if full_bleed do
        {
          max(assigns.body_height, 1),
          max(assigns.body_width, 1),
          max(assigns.body_height, 1)
        }
      else
        panel_height = max(assigns.body_height - 2, 1)
        live_width = max(assigns.body_width - 2, 1)
        live_height = max(panel_height - 2, 1)
        {panel_height, live_width, live_height}
      end

    assigns =
      assigns
      |> assign(full_bleed: full_bleed)
      |> assign(hosted_live: hosted_live)
      |> assign(persistent: persistent)
      |> assign(panel_height: panel_height)
      |> assign(live_width: live_width)
      |> assign(live_height: live_height)
      |> assign(live_instance_id: assigns.id)
      |> assign(controls_id: "#{assigns.id}-slide-controls")
      |> assign(merged_start_opts: merge_start_opts(assigns.start_opts, width: live_width, height: live_height))

    ~H"""
    <box class="width-full height-full">
      <box :if={not @full_bleed} class="bold text-primary">{@title}</box>
      <box
        id={"#{@id}-panel"}
        focus-within={true}
        style={%{height: @panel_height}}
        class={
          if(@full_bleed,
            do: "bg-panel width-full",
            else: "border border-stroke focus:border-primary bg-panel width-full"
          )
        }
      >
        <box :if={not @hosted_live} class="width-full height-full">
          <live
            :if={@view}
            id={@live_instance_id}
            view={@view}
            class="width-full height-full overflow-hidden"
            start_opts={@merged_start_opts}
            persistent={@persistent}
          >
          </live>
        </box>
        <box :if={@hosted_live} class="width-full height-full"></box>
        <box :if={is_nil(@view)} class="text-muted text-center">
          [ missing live view ]
        </box>
      </box>
      <box :if={not @full_bleed} id={@controls_id} focusable class="text-muted">
        Tab focus · arrows navigate slides
      </box>
    </box>
    """
  end

  defp merge_start_opts(start_opts, defaults) when is_list(start_opts) do
    Keyword.merge(defaults, start_opts)
  end

  defp merge_start_opts(start_opts, defaults) when is_function(start_opts, 2) do
    [width: width, height: height] = defaults
    start_opts.(width, height)
  end

  defp merge_start_opts(_start_opts, defaults), do: defaults

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
