defmodule EasyBreezy.SourceEditor do
  @moduledoc false

  @escape_keys ["Escape", "Esc", "\e", "27u"]
  @enter_keys ["Enter", "\r", "\n"]
  @backspace_keys ["Backspace", "\b", "\x7F"]
  @special_keys [
    "ArrowUp",
    "ArrowDown",
    "ArrowLeft",
    "ArrowRight",
    "PageUp",
    "PageDown",
    "Home",
    "End",
    "Delete",
    "Insert",
    "Tab"
  ]

  defstruct lines: [""],
            row: 0,
            col: 0,
            preferred_col: nil,
            mode: :normal,
            command: "",
            pending: nil,
            undo: [],
            saved_source: "",
            dirty?: false,
            message: nil

  def new(source) when is_binary(source) do
    %__MODULE__{lines: source_lines(source), saved_source: source}
  end

  def source(%__MODULE__{lines: lines}), do: Enum.join(lines, "\n")

  def snapshot(nil), do: nil
  def snapshot(%__MODULE__{} = editor), do: %{editor | undo: []}

  def mark_saved(%__MODULE__{} = editor) do
    %{editor | saved_source: source(editor), dirty?: false, message: nil, pending: nil}
  end

  def put_message(%__MODULE__{} = editor, message) do
    %{editor | message: message, pending: nil}
  end

  def status(%__MODULE__{mode: :insert}), do: "-- INSERT --"
  def status(%__MODULE__{mode: :command, command: command}), do: ":" <> command

  def status(%__MODULE__{} = editor) do
    cond do
      is_binary(editor.message) and editor.message != "" -> editor.message
      editor.pending == :delete -> "d"
      editor.pending == :goto -> "g"
      true -> "NORMAL"
    end
  end

  def position(%__MODULE__{} = editor), do: {editor.row + 1, editor.col + 1}

  def visible_rows(%__MODULE__{} = editor, height, width)
      when is_integer(height) and is_integer(width) do
    height = max(height, 1)
    width = max(width, 1)
    first_row = max(editor.row - height + 1, 0)
    last_row = min(first_row + height - 1, length(editor.lines) - 1)

    if first_row > last_row do
      []
    else
      Enum.map(first_row..last_row, fn row ->
        line = Enum.at(editor.lines, row, "")
        cursor_col = if row == editor.row, do: editor.col, else: nil
        row_parts(line, row, cursor_col, width)
      end)
    end
  end

  def handle_key(%__MODULE__{} = editor, %{"key" => key} = event) do
    editor = %{editor | message: nil}

    case editor.mode do
      :normal -> handle_normal(editor, key)
      :insert -> handle_insert(editor, key, event)
      :command -> handle_command(editor, key, event)
    end
  end

  def handle_key(%__MODULE__{} = editor, _event), do: {:ok, editor}

  defp handle_normal(editor, key) when key in @escape_keys,
    do: {:ok, %{editor | pending: nil}}

  defp handle_normal(editor, "h"), do: {:ok, move_horizontal(editor, -1)}
  defp handle_normal(editor, "ArrowLeft"), do: {:ok, move_horizontal(editor, -1)}
  defp handle_normal(editor, "l"), do: {:ok, move_horizontal(editor, 1)}
  defp handle_normal(editor, "ArrowRight"), do: {:ok, move_horizontal(editor, 1)}
  defp handle_normal(editor, "j"), do: {:ok, move_vertical(editor, 1)}
  defp handle_normal(editor, "ArrowDown"), do: {:ok, move_vertical(editor, 1)}
  defp handle_normal(editor, "k"), do: {:ok, move_vertical(editor, -1)}
  defp handle_normal(editor, "ArrowUp"), do: {:ok, move_vertical(editor, -1)}
  defp handle_normal(editor, "0"), do: {:ok, %{editor | col: 0, preferred_col: nil}}
  defp handle_normal(editor, "Home"), do: {:ok, %{editor | col: 0, preferred_col: nil}}
  defp handle_normal(editor, "$"), do: {:ok, move_to_line_end(editor)}
  defp handle_normal(editor, "End"), do: {:ok, move_to_line_end(editor)}
  defp handle_normal(editor, "w"), do: {:ok, move_word_forward(editor)}
  defp handle_normal(editor, "b"), do: {:ok, move_word_backward(editor)}
  defp handle_normal(editor, "G"), do: {:ok, move_to_row(editor, length(editor.lines) - 1)}

  defp handle_normal(%{pending: :goto} = editor, "g"),
    do: {:ok, editor |> Map.put(:pending, nil) |> move_to_row(0)}

  defp handle_normal(editor, "g"), do: {:ok, %{editor | pending: :goto}}

  defp handle_normal(%{pending: :delete} = editor, "d"),
    do: {:ok, editor |> Map.put(:pending, nil) |> delete_line()}

  defp handle_normal(editor, "d"), do: {:ok, %{editor | pending: :delete}}
  defp handle_normal(editor, "x"), do: {:ok, delete_character(editor)}
  defp handle_normal(editor, "u"), do: {:ok, undo(editor)}

  defp handle_normal(editor, "i"),
    do: {:ok, editor |> begin_change() |> enter_insert(editor.col)}

  defp handle_normal(editor, "a") do
    col = min(editor.col + 1, line_length(editor))
    {:ok, editor |> begin_change() |> enter_insert(col)}
  end

  defp handle_normal(editor, "o"), do: {:ok, open_line(editor, :below)}
  defp handle_normal(editor, "O"), do: {:ok, open_line(editor, :above)}

  defp handle_normal(editor, ":"),
    do: {:ok, %{editor | mode: :command, command: "", pending: nil}}

  defp handle_normal(%{pending: pending} = editor, key) when not is_nil(pending) do
    handle_normal(%{editor | pending: nil}, key)
  end

  defp handle_normal(editor, _key), do: {:ok, editor}

  defp handle_insert(editor, key, _event) when key in @escape_keys do
    {:ok, editor |> Map.merge(%{mode: :normal, col: max(editor.col - 1, 0)}) |> clamp_cursor()}
  end

  defp handle_insert(editor, key, _event) when key in @enter_keys,
    do: {:ok, split_line(editor)}

  defp handle_insert(editor, key, _event) when key in @backspace_keys,
    do: {:ok, backspace(editor)}

  defp handle_insert(editor, "ArrowLeft", _event), do: {:ok, move_horizontal(editor, -1)}
  defp handle_insert(editor, "ArrowRight", _event), do: {:ok, move_horizontal(editor, 1)}
  defp handle_insert(editor, "ArrowUp", _event), do: {:ok, move_vertical(editor, -1)}
  defp handle_insert(editor, "ArrowDown", _event), do: {:ok, move_vertical(editor, 1)}
  defp handle_insert(editor, "Tab", _event), do: {:ok, insert_text(editor, "  ")}

  defp handle_insert(editor, key, event) do
    if printable_input?(key, event) do
      {:ok, insert_text(editor, key)}
    else
      {:ok, editor}
    end
  end

  defp handle_command(editor, key, _event) when key in @escape_keys,
    do: {:ok, %{editor | mode: :normal, command: ""}}

  defp handle_command(editor, key, _event) when key in @enter_keys do
    command = String.trim(editor.command)
    {:command, command, %{editor | mode: :normal, command: ""}}
  end

  defp handle_command(editor, key, _event) when key in @backspace_keys do
    command = editor.command |> String.graphemes() |> Enum.drop(-1) |> Enum.join()
    {:ok, %{editor | command: command}}
  end

  defp handle_command(editor, key, event) do
    if printable_input?(key, event) do
      {:ok, %{editor | command: editor.command <> key}}
    else
      {:ok, editor}
    end
  end

  defp source_lines(source), do: String.split(source, "\n", trim: false)

  defp row_parts(line, row, nil, width) do
    %{number: row + 1, before: display_slice(line, 0, width), cursor: nil, after: ""}
  end

  defp row_parts(line, row, cursor_col, width) do
    graphemes = String.graphemes(line)
    horizontal_offset = max(cursor_col - width + 1, 0)
    visible = Enum.slice(graphemes, horizontal_offset, width)
    visible_cursor = cursor_col - horizontal_offset

    %{
      number: row + 1,
      before: visible |> Enum.take(visible_cursor) |> display_graphemes(),
      cursor: visible |> Enum.at(visible_cursor, " ") |> display_grapheme(),
      after: visible |> Enum.drop(visible_cursor + 1) |> display_graphemes()
    }
  end

  defp display_slice(line, start, count) do
    line |> String.graphemes() |> Enum.slice(start, count) |> display_graphemes()
  end

  defp display_graphemes(graphemes), do: graphemes |> Enum.map(&display_grapheme/1) |> Enum.join()
  defp display_grapheme("\t"), do: "  "
  defp display_grapheme(grapheme), do: grapheme

  defp move_horizontal(editor, offset) do
    max_col = cursor_max_col(editor)
    %{editor | col: (editor.col + offset) |> max(0) |> min(max_col), preferred_col: nil}
  end

  defp move_vertical(editor, offset) do
    preferred_col = editor.preferred_col || editor.col
    row = (editor.row + offset) |> max(0) |> min(length(editor.lines) - 1)
    editor = %{editor | row: row, preferred_col: preferred_col}
    %{editor | col: min(preferred_col, cursor_max_col(editor))}
  end

  defp move_to_row(editor, row) do
    editor = %{editor | row: row |> max(0) |> min(length(editor.lines) - 1), preferred_col: nil}
    %{editor | col: min(editor.col, cursor_max_col(editor))}
  end

  defp move_to_line_end(editor),
    do: %{editor | col: cursor_max_col(editor), preferred_col: nil}

  defp move_word_forward(editor) do
    current = {editor.row, editor.col}

    target =
      editor.lines
      |> word_start_positions()
      |> Enum.find(fn {row, col, _grapheme} -> {row, col} > current end)

    case target do
      nil -> editor |> move_to_row(length(editor.lines) - 1) |> move_to_line_end()
      position -> move_to_position(editor, position)
    end
  end

  defp move_word_backward(editor) do
    current = {editor.row, editor.col}

    target =
      editor.lines
      |> word_start_positions()
      |> Enum.take_while(fn {row, col, _grapheme} -> {row, col} < current end)
      |> List.last()

    case target do
      nil -> %{editor | row: 0, col: 0, preferred_col: nil}
      position -> move_to_position(editor, position)
    end
  end

  defp word_start_positions(lines) do
    lines
    |> buffer_positions()
    |> Enum.reduce({[], nil}, fn {row, col, grapheme} = position, {starts, previous} ->
      start? =
        word_character?(grapheme) and
          case previous do
            {previous_row, previous_col, previous_grapheme} ->
              previous_row != row or previous_col != col - 1 or
                not word_character?(previous_grapheme)

            nil ->
              true
          end

      {if(start?, do: [position | starts], else: starts), position}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp move_to_position(editor, {row, col, _grapheme}),
    do: %{editor | row: row, col: col, preferred_col: nil}

  defp buffer_positions(lines) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, row} ->
      line
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.map(fn {grapheme, col} -> {row, col, grapheme} end)
    end)
  end

  defp word_character?(grapheme), do: String.match?(grapheme, ~r/^[[:alnum:]_]$/u)

  defp enter_insert(editor, col),
    do: %{editor | mode: :insert, col: col, pending: nil, preferred_col: nil}

  defp open_line(editor, where) do
    editor = begin_change(editor)
    index = if where == :above, do: editor.row, else: editor.row + 1
    lines = List.insert_at(editor.lines, index, "")
    %{editor | lines: lines, row: index, col: 0, mode: :insert, dirty?: true}
  end

  defp insert_text(editor, text) do
    graphemes = line_graphemes(editor)
    insertion = String.graphemes(text)
    updated = List.insert_at(graphemes, editor.col, insertion) |> List.flatten() |> Enum.join()

    editor
    |> replace_current_line(updated)
    |> Map.put(:col, editor.col + length(insertion))
    |> update_dirty()
  end

  defp split_line(editor) do
    graphemes = line_graphemes(editor)
    before = graphemes |> Enum.take(editor.col) |> Enum.join()
    trailing = graphemes |> Enum.drop(editor.col) |> Enum.join()

    lines =
      editor.lines
      |> List.replace_at(editor.row, before)
      |> List.insert_at(editor.row + 1, trailing)

    %{editor | lines: lines, row: editor.row + 1, col: 0, preferred_col: nil}
    |> update_dirty()
  end

  defp backspace(%{col: col} = editor) when col > 0 do
    graphemes = line_graphemes(editor)
    updated = List.delete_at(graphemes, col - 1) |> Enum.join()

    editor
    |> replace_current_line(updated)
    |> Map.put(:col, col - 1)
    |> update_dirty()
  end

  defp backspace(%{row: row} = editor) when row > 0 do
    previous = Enum.at(editor.lines, row - 1)
    current = Enum.at(editor.lines, row)
    lines = editor.lines |> List.replace_at(row - 1, previous <> current) |> List.delete_at(row)

    %{editor | lines: lines, row: row - 1, col: String.length(previous), preferred_col: nil}
    |> update_dirty()
  end

  defp backspace(editor), do: editor

  defp delete_character(editor) do
    graphemes = line_graphemes(editor)

    if graphemes == [] do
      editor
    else
      editor = begin_change(editor)
      updated = List.delete_at(graphemes, editor.col) |> Enum.join()
      editor |> replace_current_line(updated) |> clamp_cursor() |> update_dirty()
    end
  end

  defp delete_line(editor) do
    editor = begin_change(editor)

    case editor.lines do
      [_only] ->
        %{editor | lines: [""], row: 0, col: 0} |> update_dirty()

      lines ->
        lines = List.delete_at(lines, editor.row)
        row = min(editor.row, length(lines) - 1)
        %{editor | lines: lines, row: row, col: 0} |> clamp_cursor() |> update_dirty()
    end
  end

  defp begin_change(editor) do
    snapshot = {editor.lines, editor.row, editor.col}
    %{editor | undo: [snapshot | Enum.take(editor.undo, 99)]}
  end

  defp undo(%{undo: []} = editor), do: %{editor | message: "Already at oldest change"}

  defp undo(%{undo: [{lines, row, col} | rest]} = editor) do
    %{editor | lines: lines, row: row, col: col, undo: rest, pending: nil}
    |> update_dirty()
    |> clamp_cursor()
  end

  defp replace_current_line(editor, line),
    do: %{editor | lines: List.replace_at(editor.lines, editor.row, line)}

  defp line_graphemes(editor), do: editor.lines |> Enum.at(editor.row, "") |> String.graphemes()
  defp line_length(editor), do: length(line_graphemes(editor))

  defp cursor_max_col(%{mode: :insert} = editor), do: line_length(editor)
  defp cursor_max_col(editor), do: max(line_length(editor) - 1, 0)

  defp clamp_cursor(editor) do
    row = editor.row |> max(0) |> min(length(editor.lines) - 1)
    editor = %{editor | row: row}
    %{editor | col: editor.col |> max(0) |> min(cursor_max_col(editor)), preferred_col: nil}
  end

  defp update_dirty(editor), do: %{editor | dirty?: source(editor) != editor.saved_source}

  defp printable_input?(key, event) when is_binary(key) do
    not Map.get(event, "ctrlKey", false) and
      not Map.get(event, "altKey", false) and
      not Map.get(event, "metaKey", false) and
      key not in @special_keys and key not in @escape_keys and key not in @enter_keys and
      key not in @backspace_keys and String.printable?(key)
  end

  defp printable_input?(_key, _event), do: false
end
