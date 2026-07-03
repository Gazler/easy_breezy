defmodule EasyBreezy.Layouts.TitleSlide do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Typography

  attr(:slide_id, :any, default: nil)
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)
  attr(:speaker, :string, default: nil)
  attr(:footer, :string, default: nil)
  attr(:render_context, :map, default: %{})

  def title_slide(assigns) do
    theme_colors = Map.get(assigns.render_context, :theme_colors, %{})
    animate_title_gradient? = Map.get(assigns.render_context, :animate_title_gradient?, true)
    animation_frozen_now = Map.get(assigns.render_context, :animation_frozen_now)

    assigns =
      assigns
      |> assign(theme_colors: theme_colors)
      |> assign(animate_title_gradient?: animate_title_gradient?)
      |> assign(animation_frozen_now: animation_frozen_now)
      |> assign(
        title_gradient_implicit:
          if(animate_title_gradient?, do: EasyBreezy.Implicit.TitleGradient, else: nil)
      )
      |> assign(
        title_gradient_id:
          "title-gradient-" <>
            Integer.to_string(:erlang.phash2(assigns.slide_id || assigns.title))
      )
      |> assign(
        footer_shimmer_id:
          "footer-shimmer-" <>
            Integer.to_string(:erlang.phash2({assigns.slide_id, assigns.footer}))
      )

    ~H"""
    <box class="grid grid-cols-1 grid-rows-3 width-full height-full">
      <box>
        <.h1
          id={@title_gradient_id}
          implicit={@title_gradient_implicit}
          class="text-gradient-to-b from-primary to-secondary"
          theme_colors={@theme_colors}
          background={Map.get(@theme_colors, :surface)}
          animation_frozen_now={@animation_frozen_now}
        >
          {@title}
        </.h1>
      </box>
      <box class="text-center">
        <box :if={@subtitle} class="text-muted">{@subtitle}</box>
        <box :if={@speaker}>
        </box>
        <box :if={@speaker}>by {@speaker}</box>
      </box>
      <box class="text-center">
        <.text
          :if={@footer}
          id={@footer_shimmer_id}
          class="text-shimmer from-muted to-text"
          theme_colors={@theme_colors}
          background={Map.get(@theme_colors, :surface)}
          animation_frozen_now={@animation_frozen_now}
        >
          {@footer}
        </.text>
      </box>
    </box>
    """
  end
end
