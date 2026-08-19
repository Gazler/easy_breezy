defmodule EasyBreezy.Layouts.PresenterSlide do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Layouts.Helpers

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :notes, :list, required: true
  attr :reveal, :any, default: :step
  attr :step, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def presenter_slide(assigns) do
    immediate? = immediate_reveal?(Map.get(assigns, :reveal, :step))
    visible_items = visible_entries(assigns.items, assigns.step, immediate?)
    visible_notes = visible_entries(assigns.notes, assigns.step, immediate?)

    item_lines =
      Enum.map(
        visible_items,
        &bullet_line(&1, 10_000, assigns.render_context, background: :panel)
      )

    note_lines =
      Enum.map(
        visible_notes,
        &bullet_line(&1, 10_000, assigns.render_context, background: :panel, foreground: :muted)
      )

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
        <box style={@panel_style} class="border border-stroke bg-panel">
          <box class="bold text-secondary"> Audience sees </box>
          <box>
          </box>
          <box :for={line <- @item_lines} class="width-full">{line}</box>
        </box>
        <box style={@panel_style} class="border border-stroke bg-panel">
          <box class="bold text-secondary"> Presenter notes </box>
          <box>
          </box>
          <box :for={line <- @note_lines} class="width-full text-muted">{line}</box>
        </box>
      </box>
    </box>
    """
  end

  defp visible_entries(entries, _step, true), do: entries
  defp visible_entries(entries, step, false), do: Enum.take(entries, step + 1)

  defp immediate_reveal?(value) when value in [:immediate, "immediate"], do: true
  defp immediate_reveal?(_value), do: false
end
