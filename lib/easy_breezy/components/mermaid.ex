defmodule EasyBreezy.Components.Mermaid do
  @moduledoc false

  use Breeze.View

  import Breeze.Blocks

  attr(:id, :string, default: "mermaid-diagram")
  attr(:source, :string, required: true)
  attr(:width, :integer, required: true)
  attr(:height, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def mermaid(assigns) do
    ansi_restore =
      assigns.render_context
      |> Map.get(:theme_colors, %{})
      |> ansi_restore()

    {class, lines} =
      case EasyBreezy.Mermaid.render(assigns.source, assigns.width, assigns.height,
             truncate?: false,
             ansi_restore: ansi_restore
           ) do
        {:ok, lines} -> {"text-secondary", lines}
        {:error, reason} -> {"text-muted", ["Unsupported Mermaid subset", "", reason]}
      end

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

  defp ansi_restore(%{secondary: {red, green, blue}, panel: {br, bg, bb}}) do
    "\e[38;2;#{red};#{green};#{blue}m\e[48;2;#{br};#{bg};#{bb}m"
  end

  defp ansi_restore(_theme_colors), do: IO.ANSI.reset()
end
