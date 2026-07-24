defmodule EasyBreezy.Layouts.MarkdownSlide do
  @moduledoc false

  use Breeze.View

  alias EasyBreezy.Components.Mermaid
  alias EasyBreezy.Deck.Markdown
  alias EasyBreezy.Markdown, as: MarkdownRenderer

  import Breeze.Blocks
  import EasyBreezy.Layouts.Helpers, only: [markdown_reset: 1]
  import EasyBreezy.Typography

  @breeze_components :text
  @breeze_components :h1
  @breeze_components :h2
  @breeze_components :h3

  attr :slide_id, :any, required: true
  attr :title, :string, default: nil
  attr :content, :string, required: true
  attr :blocks, :list, default: nil
  attr :step, :integer, default: 0
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def markdown_slide(assigns) do
    title_height = if assigns.title, do: 2, else: 0
    markdown_height = max(assigns.body_height + 2 - title_height, 1)
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
            assigns.step,
            markdown_width,
            markdown_height
          )
      )

    ~H"""
    <box class="width-full height-full">
      <box :if={@title} class="bold text-primary">{@title}</box>
      <box :if={@title}>
      </box>
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
    <box :if={Map.get(@block, :blank_after?, false)}>
    </box>
    <box :if={@block.type == :mermaid}>
      <box :for={line <- @block.lines} class={@block.class}>{line}</box>
      <box>
      </box>
    </box>
    <.breeze_content :if={@block.type == :breeze} block={@block}/>
    """
  end

  attr :block, :map, required: true

  defp breeze_content(assigns) do
    {Map.fetch!(assigns.block, :template), Map.get(assigns.block, :assigns, %{})}
  end

  defp render_blocks(blocks, assigns, step, markdown_width, markdown_height) do
    render_opts = markdown_render_opts(assigns.render_context)
    env = __ENV__

    blocks
    |> visible_blocks(step)
    |> with_next_block()
    |> Enum.map(fn
      {%{type: :markdown, content: content}, next_block} ->
        %{
          type: :markdown,
          rendered: MarkdownRenderer.render(content, markdown_width, render_opts),
          blank_after?: blank_after_markdown?(content, next_block)
        }

      {%{type: :mermaid, content: source}, _next_block} ->
        {class, lines} =
          Mermaid.render_lines(
            source,
            markdown_width,
            markdown_height,
            assigns.render_context
          )

        %{type: :mermaid, class: class, lines: lines}

      {%{type: :breeze, content: source}, _next_block} ->
        %{
          type: :breeze,
          template: Breeze.Template.compile!(source, env),
          assigns: breeze_assigns(assigns, markdown_width, markdown_height)
        }
    end)
  end

  defp with_next_block([]), do: []
  defp with_next_block([_ | rest] = blocks), do: Enum.zip(blocks, rest ++ [nil])

  defp blank_after_markdown?(_content, nil), do: false

  defp blank_after_markdown?(content, next_block) do
    MarkdownRenderer.ends_with_code_fence?(content) or starts_with_code_fence?(next_block)
  end

  defp starts_with_code_fence?(%{type: :markdown, content: content}) do
    MarkdownRenderer.starts_with_code_fence?(content)
  end

  defp starts_with_code_fence?(_block), do: false

  defp visible_blocks(blocks, step) do
    Enum.filter(blocks, &(Map.get(&1, :step, 0) <= step))
  end

  defp breeze_assigns(assigns, markdown_width, markdown_height) do
    assigns
    |> Map.take([:slide_id, :title, :render_context])
    |> Map.merge(%{
      body_width: assigns.body_width,
      body_height: assigns.body_height,
      markdown_width: markdown_width,
      markdown_height: markdown_height
    })
  end

  defp markdown_render_opts(render_context) do
    [
      reset: markdown_reset(render_context),
      theme_colors: Map.get(render_context, :theme_colors, %{}),
      code_theme: Map.get(render_context, :code_theme, "github_dark"),
      code_background: :panel
    ]
  end
end
