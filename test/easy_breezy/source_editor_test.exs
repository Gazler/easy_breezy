defmodule EasyBreezy.SourceEditorTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.SourceEditor

  test "moves with Vim keys and preserves the preferred column" do
    editor = SourceEditor.new("one two\nx\nthree")

    editor = editor |> key("$") |> key("j")
    assert SourceEditor.position(editor) == {2, 1}

    editor = key(editor, "j")
    assert SourceEditor.position(editor) == {3, 5}

    editor = editor |> key("g") |> key("g")
    assert SourceEditor.position(editor) == {1, 5}

    editor = key(editor, "G")
    assert SourceEditor.position(editor) == {3, 5}
  end

  test "supports insert, line editing, delete, and undo" do
    editor = SourceEditor.new("one")

    editor = editor |> key("i") |> key("X") |> key("Escape")
    assert SourceEditor.source(editor) == "Xone"
    assert editor.dirty?

    editor = key(editor, "x")
    assert SourceEditor.source(editor) == "one"

    editor = key(editor, "u")
    assert SourceEditor.source(editor) == "Xone"

    editor = editor |> key("o") |> key("two") |> key("Escape")
    assert SourceEditor.source(editor) == "Xone\ntwo"

    editor = editor |> key("d") |> key("d")
    assert SourceEditor.source(editor) == "Xone"
  end

  test "moves between word starts with w and b" do
    editor = SourceEditor.new("one two") |> key("$") |> key("b")
    assert SourceEditor.position(editor) == {1, 5}

    editor = key(editor, "b")
    assert SourceEditor.position(editor) == {1, 1}

    editor = key(editor, "w")
    assert SourceEditor.position(editor) == {1, 5}
  end

  test "splits and joins lines in insert mode" do
    editor = SourceEditor.new("onetwo")

    editor = editor |> key("l") |> key("l") |> key("l") |> key("i") |> key("Enter")
    assert SourceEditor.source(editor) == "one\ntwo"

    editor = key(editor, "Backspace")
    assert SourceEditor.source(editor) == "onetwo"
  end

  test "returns ex commands to the owning view" do
    editor = SourceEditor.new("body") |> key(":") |> key("w")

    assert {:command, "w", editor} = SourceEditor.handle_key(editor, %{"key" => "Enter"})
    assert editor.mode == :normal
    assert editor.command == ""
  end

  test "renders the cursor inside a bounded viewport" do
    editor = SourceEditor.new("one\ntwo\nthree") |> key("G") |> key("$")

    assert [
             %{number: 2, cursor: nil},
             %{number: 3, before: "thre", cursor: "e", after: ""}
           ] = SourceEditor.visible_rows(editor, 2, 10)
  end

  defp key(editor, key) do
    assert {:ok, editor} = SourceEditor.handle_key(editor, %{"key" => key})
    editor
  end
end
