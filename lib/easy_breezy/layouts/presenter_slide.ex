defmodule EasyBreezy.Layouts.PresenterSlide do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Layouts.Helpers

  attr(:title, :string, required: true)
  attr(:items, :list, required: true)
  attr(:notes, :list, required: true)
  attr(:step, :integer, required: true)
  attr(:body_height, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def presenter_slide(assigns) do
    visible_items = Enum.take(assigns.items, assigns.step + 1)
    visible_notes = Enum.take(assigns.notes, assigns.step + 1)
    item_lines = Enum.map(visible_items, &bullet_line(&1, 28))
    note_lines = Enum.map(visible_notes, &bullet_line(&1, 28))
    panel_height = max(assigns.body_height, 4)

    assigns =
      assigns
      |> assign(item_lines: item_lines)
      |> assign(note_lines: note_lines)
      |> assign(panel_height: panel_height)
      |> assign(panel_style: %{height: panel_height})

    ~H"""
    <box class="width-full height-full">
      <box class="bold text-primary">{@title}</box>
      <box>
      </box>
      <box style={@panel_style} class="grid grid-cols-2 width-full">
        <box style={@panel_style} class="border-rounded border border-stroke bg-panel">
          <box class="bold text-secondary"> Audience sees </box>
          <box>
          </box>
          <box :for={line <- @item_lines}>{line}</box>
        </box>
        <box style={@panel_style} class="border-rounded border border-stroke bg-panel">
          <box class="bold text-secondary"> Presenter notes </box>
          <box>
          </box>
          <box :for={line <- @note_lines} class="text-muted">{line}</box>
        </box>
      </box>
    </box>
    """
  end
end
