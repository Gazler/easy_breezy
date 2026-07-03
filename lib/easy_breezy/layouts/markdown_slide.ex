defmodule EasyBreezy.Layouts.MarkdownSlide do
  @moduledoc false

  use Breeze.View

  alias EasyBreezy.Components.Mermaid
  alias EasyBreezy.Deck.Markdown

  import Breeze.Blocks

  attr :slide_id, :any, required: true
  attr :title, :string, default: nil
  attr :content, :string, required: true
  attr :blocks, :list, default: nil
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def markdown_slide(assigns) do
    markdown_height = max(assigns.body_height - 2, 1)
    markdown_width = assigns.body_width + 4

    assigns =
      assigns
      |> assign(
        markdown_id:
          "markdown-slide-" <>
            Integer.to_string(
              :erlang.phash2(assigns.slide_id || assigns.title || assigns.content)
            )
      )
      |> assign(markdown_height: markdown_height)
      |> assign(
        blocks:
          render_blocks(
            assigns.blocks || Markdown.content_blocks(assigns.content),
            assigns,
            markdown_width,
            markdown_height
          )
      )

    ~H"""
    <box class="width-full height-full">
      <box :if={@title} class="bold text-primary">{@title}</box>
      <.scroll
        id={@markdown_id}
        class="height-full overflow-scroll scrollbar-arrows"
        style={%{height: @markdown_height}}
      >
        <.markdown_content_block :for={block <- @blocks} block={block}/>
      </.scroll>
    </box>
    """
  end

  attr :block, :map, required: true

  defp markdown_content_block(assigns) do
    ~H"""
    <box :if={@block.type == :markdown}>{@block.rendered}</box>
    <box :if={@block.type == :mermaid}>
      <box :for={line <- @block.lines} class={@block.class}>{line}</box>
      <box>
      </box>
    </box>
    """
  end

  defp render_blocks(blocks, assigns, markdown_width, markdown_height) do
    reset = markdown_restore(assigns.render_context)

    Enum.map(blocks, fn
      %{type: :markdown, content: content} ->
        %{
          type: :markdown,
          rendered: Breeze.Markdown.render(content, markdown_width, reset: reset)
        }

      %{type: :mermaid, content: source} ->
        {class, lines} =
          Mermaid.render_lines(
            source,
            markdown_width,
            markdown_height,
            assigns.render_context
          )

        %{type: :mermaid, class: class, lines: lines}
    end)
  end

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
