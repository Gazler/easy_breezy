defmodule EasyBreezy.Components.Mermaid do
  @moduledoc false

  use Breeze.View

  import Breeze.Blocks

  attr :id, :string, default: "mermaid-diagram"
  attr :source, :string, required: true
  attr :width, :integer, required: true
  attr :height, :integer, required: true
  attr :render_context, :map, default: %{}

  def mermaid(assigns) do
    {class, lines} =
      render_lines(assigns.source, assigns.width, assigns.height, assigns.render_context)

    assigns =
      assigns
      |> assign(class: class)
      |> assign(lines: lines)
      |> assign(scroll_class: "width-full height-#{max(assigns.height, 1)} overflow-scroll")

    ~H"""
    <.scroll id={@id} class={@scroll_class}>
      <box :for={line <- @lines} class={@class}>{line}</box>
    </.scroll>
    """
  end

  def render_lines(source, width, height \\ 1, render_context \\ %{}) do
    ansi_restore =
      render_context
      |> Map.get(:theme_colors, %{})
      |> ansi_restore()

    case EasyBreezy.Mermaid.render(source, width, height,
           truncate?: false,
           ansi_restore: ansi_restore
         ) do
      {:ok, lines} -> {"text-secondary", lines}
      {:error, reason} -> {"text-muted", ["Unsupported Mermaid subset", "", reason]}
    end
  end

  defp ansi_restore(%{secondary: {red, green, blue}}) do
    "\e[38;2;#{red};#{green};#{blue}m"
  end

  defp ansi_restore(%{secondary: color}) when is_integer(color),
    do: "\e[#{ansi_foreground(color)}m"

  defp ansi_restore(_theme_colors), do: IO.ANSI.reset()

  defp ansi_foreground(color) when color in 0..7, do: 30 + color
  defp ansi_foreground(color) when color in 8..15, do: 90 + color - 8
  defp ansi_foreground(color), do: "38;5;#{color}"
end
