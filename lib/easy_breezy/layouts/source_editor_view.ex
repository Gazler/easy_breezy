defmodule EasyBreezy.Layouts.SourceEditorView do
  @moduledoc false

  use Breeze.View

  alias EasyBreezy.SourceEditor

  attr :title, :string, required: true
  attr :editor, :any, required: true
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def source_editor_view(assigns) do
    editor_height = max(assigns.body_height - 2, 1)
    line_number_width = assigns.editor.lines |> length() |> max(1) |> Integer.digits() |> length()
    gutter_width = line_number_width + 2
    source_width = max(assigns.body_width - gutter_width - 1, 1)
    theme_colors = Map.get(assigns.render_context, :theme_colors, %{})
    {row, col} = SourceEditor.position(assigns.editor)

    assigns =
      assigns
      |> assign(editor_height: editor_height)
      |> assign(gutter_style: %{width: gutter_width})
      |> assign(body_style: %{position: :absolute, top: 1, height: editor_height})
      |> assign(rows: SourceEditor.visible_rows(assigns.editor, editor_height, source_width))
      |> assign(status: SourceEditor.status(assigns.editor))
      |> assign(position: "#{row}:#{col}")
      |> assign(
        cursor_style: %{
          background_color: Map.get(theme_colors, :primary),
          foreground_color: Map.get(theme_colors, :surface)
        }
      )

    ~H"""
    <box class="width-full height-full bg-panel overflow-hidden">
      <box class="absolute top-0 width-full height-1 inline bg-panel">
        <box class="bold text-primary">{@title}</box>
        <box :if={@editor.dirty?} class="text-warning"> [+]</box>
        <box style="width-full text-right" class="text-muted">Vim-like editor</box>
      </box>
      <box style={@body_style} class="width-full overflow-hidden bg-panel">
        <box :for={line <- @rows} class="width-full height-1 inline bg-panel">
          <box style={@gutter_style} class="text-muted text-right">{line.number} </box>
          <box>{line.before}</box>
          <box :if={!is_nil(line.cursor)} class="bold" style={@cursor_style}>{line.cursor}</box>
          <box>{line.after}</box>
        </box>
      </box>
      <box class="absolute bottom-0 width-full height-1 inline bg-surface">
        <box class="bold text-secondary"> {@status} </box>
        <box style="width-full text-right" class="text-muted"> {@position} </box>
      </box>
    </box>
    """
  end
end
