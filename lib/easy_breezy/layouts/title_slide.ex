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

    assigns =
      assigns
      |> assign(theme_colors: theme_colors)
      |> assign(
        title_gradient_id:
          "title-gradient-" <>
            Integer.to_string(:erlang.phash2(assigns.slide_id || assigns.title))
      )

    ~H"""
    <box class="grid grid-cols-1 grid-rows-3 width-full height-full">
      <box>
        <.h1
          id={@title_gradient_id}
          implicit={EasyBreezy.Implicit.TitleGradient}
          class="text-gradient-to-b from-primary to-secondary"
          theme_colors={@theme_colors}
          background={Map.get(@theme_colors, :surface)}
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
        <box class="text-muted">{@footer}</box>
      </box>
    </box>
    """
  end
end
