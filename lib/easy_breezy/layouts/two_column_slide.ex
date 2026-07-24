defmodule EasyBreezy.Layouts.TwoColumnSlide do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Components.Mermaid
  import EasyBreezy.Layouts.Helpers

  attr :title, :string, required: true
  attr :left_title, :string, default: nil
  attr :left_items, :list, default: []
  attr :left_lines, :list, default: []
  attr :left_mode, :atom, default: :text
  attr :left_path, :string, default: nil
  attr :left_mermaid_source, :string, default: nil
  attr :right_title, :string, default: nil
  attr :right_lines, :list, default: []
  attr :right_notice, :string, default: nil
  attr :right_mode, :atom, default: :text
  attr :right_path, :string, default: nil
  attr :right_mermaid_source, :string, default: nil
  attr :reveal, :any, default: :step
  attr :step, :integer, required: true
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def two_column_slide(assigns) do
    left_items = Map.get(assigns, :left_items, [])
    left_lines = Map.get(assigns, :left_lines, [])
    left_mode = Map.get(assigns, :left_mode, :text)
    left_mermaid_source = Map.get(assigns, :left_mermaid_source)
    left_path = Map.get(assigns, :left_path)
    left_title = Map.get(assigns, :left_title)
    right_lines = Map.get(assigns, :right_lines, [])
    right_mode = Map.get(assigns, :right_mode, :text)
    right_mermaid_source = Map.get(assigns, :right_mermaid_source)
    right_path = Map.get(assigns, :right_path)
    right_title = Map.get(assigns, :right_title)
    reveal = Map.get(assigns, :reveal, :step)
    immediate? = immediate_reveal?(reveal)
    image_active? = Map.get(assigns.render_context, :render_images?, true) != false
    image_scope = Map.get(assigns.render_context, :image_scope, "slide")
    visible_items = visible_items(left_items, assigns.step, immediate?)

    left_width = max(div(assigns.body_width, 2) - 4, 16)
    right_width = max(div(assigns.body_width, 2) - 4, 16)
    panel_height = max(assigns.body_height, 4)
    code_lines = max(panel_height - 4, 1)

    left_item_lines =
      Enum.map(
        visible_items,
        &bullet_line(&1, left_width, assigns.render_context, background: :panel)
      )

    left_lines =
      case left_lines do
        [] -> Enum.map(left_item_lines, &{"", &1})
        lines -> Enum.map(lines, &normalize_line/1)
      end

    visible_right_lines =
      right_lines
      |> Enum.flat_map(&wrap_code_line(&1, right_width))
      |> Enum.take(code_lines)

    right_notice = Map.get(assigns, :right_notice)

    show_right_lines? =
      right_mode == :text and
        (right_notice == nil or immediate? or assigns.step >= length(left_items))

    image_mode? = left_mode == :image or right_mode == :image
    left_header_height = if(left_title, do: 2, else: 0)
    right_header_height = if(right_title, do: 2, else: 0)
    left_content_height = max(panel_height - left_header_height - 2, 1)
    right_content_height = max(panel_height - right_header_height - 2, 1)
    left_mermaid_width = max(left_width - 2, 1)
    right_mermaid_width = max(right_width - 2, 1)

    assigns =
      assigns
      |> assign(
        left_items: left_items,
        reveal: reveal,
        left_mermaid_source: left_mermaid_source,
        left_mode: left_mode,
        left_path: left_path,
        left_title: left_title,
        right_lines: right_lines,
        right_mermaid_source: right_mermaid_source,
        right_mode: right_mode,
        right_path: right_path,
        right_title: right_title,
        image_active?: image_active?
      )
      |> assign(image_scope: image_scope)
      |> assign(left_lines: left_lines)
      |> assign(panel_height: panel_height)
      |> assign(visible_right_lines: visible_right_lines)
      |> assign(right_notice: right_notice)
      |> assign(show_right_lines?: show_right_lines?)
      |> assign(panel_style: %{height: panel_height})
      |> assign(left_content_height: left_content_height)
      |> assign(right_content_height: right_content_height)
      |> assign(left_mermaid_width: left_mermaid_width)
      |> assign(right_mermaid_width: right_mermaid_width)
      |> assign(left_image_style: %{height: left_content_height})
      |> assign(right_image_style: %{height: right_content_height})
      |> assign(
        left_panel_class:
          if(image_mode?,
            do: "",
            else: "border-rounded border border-stroke bg-panel"
          ),
        right_panel_class:
          if(image_mode?,
            do: "",
            else: "border-rounded border border-stroke bg-panel"
          )
      )

    ~H"""
    <box class="width-full height-full">
      <box class="bold text-primary">{@title}</box>
      <box>
      </box>
      <box style={@panel_style} class="grid grid-cols-2 width-full">
        <box style={@panel_style} class={@left_panel_class}>
          <box :if={@left_title} class="bold text-secondary">{" #{@left_title} "}</box>
          <box :if={@left_title}>
          </box>
          <box :for={{class, line} <- @left_lines} :if={@left_mode == :text} class={class}>
            {line}
          </box>
          <.mermaid
            :if={@left_mode == :mermaid}
            id="slide-mermaid-left"
            source={@left_mermaid_source || ""}
            width={@left_mermaid_width}
            height={@left_content_height}
          />
          <box
            :if={@left_mode == :image}
            id="slide-image-left"
            implicit={EasyBreezy.Slideshow.KittyImage}
            image-path={@left_path}
            image-mode="show"
            image-active={@image_active?}
            image-scope={"#{@image_scope}:left"}
            style={@left_image_style}
            class="width-full border-rounded border border-stroke bg-panel"
          >
          </box>
        </box>
        <box style={@panel_style} class={@right_panel_class}>
          <box :if={@right_title} class="bold text-secondary">{" #{@right_title} "}</box>
          <box :if={@right_title}>
          </box>
          <box :if={@right_notice && not @show_right_lines?} class="text-muted">{@right_notice}</box>
          <box
            :for={line <- @visible_right_lines}
            :if={@right_mode == :text && @show_right_lines?}
            class="text-accent"
          >
            {line}
          </box>
          <.mermaid
            :if={@right_mode == :mermaid}
            id="slide-mermaid-right"
            source={@right_mermaid_source || ""}
            width={@right_mermaid_width}
            height={@right_content_height}
          />
          <box
            :if={@right_mode == :image}
            id="slide-image"
            implicit={EasyBreezy.Slideshow.KittyImage}
            image-path={@right_path}
            image-mode="show"
            image-active={@image_active?}
            image-scope={"#{@image_scope}:right"}
            style={@right_image_style}
            class="width-full border-rounded border border-stroke bg-panel"
          >
          </box>
        </box>
      </box>
    </box>
    """
  end

  defp normalize_line({class, line}), do: {class, line}
  defp normalize_line(line), do: {"", line}

  defp visible_items(items, _step, true), do: items

  defp visible_items(items, step, false) do
    Enum.take(items, min(step + 1, length(items)))
  end

  defp immediate_reveal?(value) when value in [:immediate, "immediate"], do: true
  defp immediate_reveal?(_value), do: false
end
