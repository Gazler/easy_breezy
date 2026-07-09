defmodule EasyBreezy.Layouts.BulletsSlide do
  @moduledoc false

  use Breeze.View

  alias EasyBreezy.Components.Mermaid
  alias EasyBreezy.Deck.Markdown

  import Breeze.Blocks
  import EasyBreezy.Layouts.Helpers

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :after_markdown, :string, default: nil
  attr :step, :integer, required: true
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def bullets_slide(assigns) do
    assigns = Map.merge(%{after_markdown: nil, render_context: %{}}, assigns)
    visible_items = Enum.take(assigns.items, assigns.step + 1)
    after_markdown? = markdown_present?(assigns.after_markdown)
    show_after_markdown? = after_markdown? and assigns.step >= length(assigns.items)

    notes =
      if length(visible_items) < length(assigns.items) or
           (after_markdown? and not show_after_markdown?) do
        "[more]"
      else
        ""
      end

    item_lines = Enum.map(visible_items, &bullet_line(&1, assigns.body_width))
    rendered_after_markdown_blocks = render_after_markdown_blocks(assigns, show_after_markdown?)

    assigns =
      assigns
      |> assign(item_lines: item_lines)
      |> assign(notes: notes)
      |> assign(rendered_after_markdown_blocks: rendered_after_markdown_blocks)

    ~H"""
    <box class="width-full height-full">
      <box class="bold text-primary">{@title}</box>
      <box>
      </box>
      <.scroll id="slide-bullets" class="height-full overflow-scroll">
        <box :for={line <- @item_lines}>{line}</box>
        <box :if={@notes != ""}>
        </box>
        <box :if={@notes != ""} class="text-muted">{@notes}</box>
        <box :if={@rendered_after_markdown_blocks != []}>
        </box>
        <.after_markdown_block :for={block <- @rendered_after_markdown_blocks} block={block}/>
      </.scroll>
    </box>
    """
  end

  attr :block, :map, required: true

  defp after_markdown_block(assigns) do
    ~H"""
    <box :if={@block.type == :markdown}>{@block.rendered}</box>
    <box :if={@block.type == :mermaid}>
      <box :for={line <- @block.lines} class={@block.class}>{line}</box>
    </box>
    """
  end

  defp render_after_markdown_blocks(_assigns, false), do: []

  defp render_after_markdown_blocks(assigns, true) do
    width = assigns.body_width
    height = max(assigns.body_height, 1)
    reset = markdown_restore(assigns.render_context)

    assigns.after_markdown
    |> Markdown.content_blocks()
    |> Enum.map(fn
      %{type: :markdown, content: content} ->
        %{type: :markdown, rendered: Breeze.Markdown.render(content, width, reset: reset)}

      %{type: :mermaid, content: source} ->
        {class, lines} = Mermaid.render_lines(source, width, height, assigns.render_context)
        %{type: :mermaid, class: class, lines: lines}
    end)
  end

  defp markdown_present?(value) when is_binary(value), do: String.trim(value) != ""
  defp markdown_present?(_value), do: false

  defp markdown_restore(%{theme_colors: %{surface: {br, bg, bb}, text: {tr, tg, tb}}}) do
    "\e[48;2;#{br};#{bg};#{bb};38;2;#{tr};#{tg};#{tb}m"
  end

  defp markdown_restore(%{theme_colors: %{surface: background, text: foreground}})
       when is_integer(background) and is_integer(foreground) do
    "\e[#{ansi_background(background)};#{ansi_foreground(foreground)}m"
  end

  defp markdown_restore(%{theme_colors: %{text: {tr, tg, tb}}}) do
    "\e[38;2;#{tr};#{tg};#{tb}m"
  end

  defp markdown_restore(%{theme_colors: %{text: foreground}}) when is_integer(foreground) do
    "\e[#{ansi_foreground(foreground)}m"
  end

  defp markdown_restore(_render_context), do: IO.ANSI.reset()

  defp ansi_foreground(color) when color in 0..7, do: 30 + color
  defp ansi_foreground(color) when color in 8..15, do: 90 + color - 8
  defp ansi_foreground(color), do: "38;5;#{color}"

  defp ansi_background(color) when color in 0..7, do: 40 + color
  defp ansi_background(color) when color in 8..15, do: 100 + color - 8
  defp ansi_background(color), do: "48;5;#{color}"
end
