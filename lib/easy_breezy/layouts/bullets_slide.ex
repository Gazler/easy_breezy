defmodule EasyBreezy.Layouts.BulletsSlide do
  @moduledoc false

  use Breeze.View

  import Breeze.Blocks
  import EasyBreezy.Layouts.Helpers

  attr(:title, :string, required: true)
  attr(:items, :list, required: true)
  attr(:step, :integer, required: true)
  attr(:body_width, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def bullets_slide(assigns) do
    visible_items = Enum.take(assigns.items, assigns.step + 1)
    notes = if length(visible_items) < length(assigns.items), do: "[more]", else: ""
    item_lines = Enum.map(visible_items, &bullet_line(&1, assigns.body_width))

    assigns =
      assigns
      |> assign(item_lines: item_lines)
      |> assign(notes: notes)

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
      </.scroll>
    </box>
    """
  end
end
