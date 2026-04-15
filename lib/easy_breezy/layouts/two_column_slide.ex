defmodule EasyBreezy.Layouts.TwoColumnSlide do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Layouts.Helpers

  attr(:title, :string, required: true)
  attr(:left_title, :string, default: nil)
  attr(:left_items, :list, default: [])
  attr(:left_lines, :list, default: [])
  attr(:right_title, :string, default: nil)
  attr(:right_lines, :list, default: [])
  attr(:right_notice, :string, default: nil)
  attr(:right_mode, :atom, default: :text)
  attr(:right_path, :string, default: nil)
  attr(:step, :integer, required: true)
  attr(:body_width, :integer, required: true)
  attr(:body_height, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def two_column_slide(assigns) do
    visible_items =
      Enum.take(assigns.left_items, min(assigns.step + 1, length(assigns.left_items)))

    left_width = max(div(assigns.body_width, 2) - 4, 16)
    right_width = max(div(assigns.body_width, 2) - 4, 16)
    panel_height = max(assigns.body_height, 4)
    code_lines = max(panel_height - 4, 1)
    left_item_lines = Enum.map(visible_items, &bullet_line(&1, left_width))

    left_lines =
      case assigns.left_lines do
        [] -> Enum.map(left_item_lines, &{"", &1})
        lines -> lines
      end

    visible_right_lines =
      assigns.right_lines
      |> Enum.flat_map(&wrap_code_line(&1, right_width))
      |> Enum.take(code_lines)

    right_notice = Map.get(assigns, :right_notice)

    show_right_lines? =
      assigns.right_mode == :text and
        (right_notice == nil or assigns.step >= length(assigns.left_items))

    assigns =
      assigns
      |> assign(left_lines: left_lines)
      |> assign(panel_height: panel_height)
      |> assign(visible_right_lines: visible_right_lines)
      |> assign(right_notice: right_notice)
      |> assign(show_right_lines?: show_right_lines?)
      |> assign(panel_style: %{height: panel_height})
      |> assign(
        left_panel_class:
          if(assigns.right_mode == :image,
            do: "",
            else: "border-rounded border border-stroke bg-panel"
          ),
        right_panel_class:
          if(assigns.right_mode == :image,
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
          <box :for={{class, line} <- @left_lines} class={class}>{line}</box>
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
          <box
            :if={@right_mode == :image}
            id="slide-image"
            implicit={EasyBreezy.Slideshow.KittyImage}
            image-path={@right_path}
            image-mode="show"
            image-active={true}
            style={@panel_style}
            class="width-full border-rounded border border-stroke bg-panel"
          >
            <box class="text-center text-muted">[ image overlay ]</box>
          </box>
        </box>
      </box>
    </box>
    """
  end
end
