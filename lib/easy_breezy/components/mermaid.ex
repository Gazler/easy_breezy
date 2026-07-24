defmodule EasyBreezy.Components.Mermaid do
  @moduledoc false

  use Breeze.View

  import Breeze.Blocks

  attr :id, :string, default: "mermaid-diagram"
  attr :source, :string, required: true
  attr :width, :integer, required: true
  attr :height, :integer, required: true

  def mermaid(assigns) do
    {class, lines} = render_lines(assigns.source, assigns.width, assigns.height)

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

  def render_lines(source, width, height \\ 1) do
    case EasyBreezy.Mermaid.render(source, width, height, truncate?: false) do
      {:ok, lines} -> {"text-secondary", lines}
      {:error, reason} -> {"text-muted", ["Unsupported Mermaid subset", "", reason]}
    end
  end
end
