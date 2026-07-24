defmodule EasyBreezy.Layouts.BulletsSlide do
  @moduledoc false

  use Breeze.View

  alias EasyBreezy.Components.Mermaid
  alias EasyBreezy.Deck.Markdown
  alias EasyBreezy.Markdown, as: MarkdownRenderer

  import Breeze.Blocks
  import EasyBreezy.Layouts.Helpers
  import EasyBreezy.Typography

  @breeze_components :text
  @breeze_components :h1
  @breeze_components :h2
  @breeze_components :h3

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :after_markdown, :string, default: nil
  attr :reveal, :any, default: :step
  attr :step, :integer, required: true
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def bullets_slide(assigns) do
    assigns = Map.merge(%{after_markdown: nil, render_context: %{}, reveal: :step}, assigns)

    immediate? = immediate_reveal?(assigns.reveal)
    visible_items = visible_items(assigns.items, assigns.step, immediate?)
    after_markdown_blocks = after_markdown_blocks(assigns.after_markdown)

    visible_after_markdown_blocks =
      visible_after_markdown_blocks(after_markdown_blocks, assigns, immediate?)

    pending_after_markdown? =
      length(visible_after_markdown_blocks) < length(after_markdown_blocks)

    notes =
      if length(visible_items) < length(assigns.items) or
           pending_after_markdown? do
        "[more]"
      else
        ""
      end

    item_lines =
      Enum.map(visible_items, &bullet_line(&1, assigns.body_width, assigns.render_context))

    rendered_after_markdown_blocks =
      render_after_markdown_blocks(assigns, visible_after_markdown_blocks)

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
    <box :if={Map.get(@block, :blank_after?, false)}>
    </box>
    <box :if={@block.type == :mermaid}>
      <box :for={line <- @block.lines} class={@block.class}>{line}</box>
    </box>
    <.breeze_content :if={@block.type == :breeze} block={@block}/>
    """
  end

  attr :block, :map, required: true

  defp breeze_content(assigns) do
    {Map.fetch!(assigns.block, :template), Map.get(assigns.block, :assigns, %{})}
  end

  defp render_after_markdown_blocks(_assigns, []), do: []

  defp render_after_markdown_blocks(assigns, blocks) do
    width = assigns.body_width + 4
    height = max(assigns.body_height, 1)
    render_opts = markdown_render_opts(assigns.render_context)
    env = __ENV__

    blocks
    |> with_next_block()
    |> Enum.map(fn
      {%{type: :markdown, content: content}, next_block} ->
        %{
          type: :markdown,
          rendered: MarkdownRenderer.render(content, width, render_opts),
          blank_after?: blank_after_markdown?(content, next_block)
        }

      {%{type: :mermaid, content: source}, _next_block} ->
        {class, lines} = Mermaid.render_lines(source, width, height)
        %{type: :mermaid, class: class, lines: lines}

      {%{type: :breeze, content: source}, _next_block} ->
        %{
          type: :breeze,
          template: Breeze.Template.compile!(source, env),
          assigns: breeze_assigns(assigns, width, height)
        }
    end)
  end

  defp with_next_block([_ | rest] = blocks), do: Enum.zip(blocks, rest ++ [nil])

  defp blank_after_markdown?(_content, nil), do: false

  defp blank_after_markdown?(content, next_block) do
    MarkdownRenderer.ends_with_code_fence?(content) or starts_with_code_fence?(next_block)
  end

  defp starts_with_code_fence?(%{type: :markdown, content: content}) do
    MarkdownRenderer.starts_with_code_fence?(content)
  end

  defp starts_with_code_fence?(_block), do: false

  defp breeze_assigns(assigns, width, height) do
    assigns
    |> Map.take([:title, :render_context])
    |> Map.merge(%{
      body_width: width,
      body_height: height
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

  defp markdown_present?(value) when is_binary(value), do: String.trim(value) != ""
  defp markdown_present?(_value), do: false

  defp visible_items(items, _step, true), do: items
  defp visible_items(items, step, false), do: Enum.take(items, step + 1)

  defp after_markdown_blocks(after_markdown) do
    if markdown_present?(after_markdown) do
      Markdown.content_blocks(after_markdown)
    else
      []
    end
  end

  defp visible_after_markdown_blocks(blocks, assigns, immediate?) do
    markdown_step = after_markdown_step(assigns, immediate?)
    Enum.filter(blocks, &(Map.get(&1, :step, 0) <= markdown_step))
  end

  defp after_markdown_step(assigns, true), do: assigns.step

  defp after_markdown_step(assigns, false), do: assigns.step - length(assigns.items)

  defp immediate_reveal?(value) when value in [:immediate, "immediate"], do: true
  defp immediate_reveal?(_value), do: false
end
