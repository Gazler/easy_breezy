defmodule EasyBreezy.DeckMarkdownEditorTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Deck.Markdown
  alias EasyBreezy.Deck.Markdown.Editor
  alias EasyBreezy.{Deck, Slide}

  test "updates parsed decks in memory" do
    deck = Markdown.parse!("# Old")

    assert {:ok, edited, :updated} = Editor.save(deck, hd(deck.slides), "# New")
    assert edited.source == "# New"
    assert hd(edited.slides).title == "New"
  end

  test "writes and reparses file-backed decks" do
    path = temp_path("written")
    source = "---\nlayout: markdown\ntitle: Old\n---\n\n# Body\n"
    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)

    deck = Markdown.load!(path)
    replacement = String.replace(hd(deck.slides).source, "title: Old", "title: New")

    assert {:ok, edited, :written} = Editor.save(deck, hd(deck.slides), replacement)
    assert edited.source_path == Path.expand(path)
    assert hd(edited.slides).title == "New"
    assert File.read!(path) == edited.source
  end

  test "does not write markdown that fails to parse" do
    path = temp_path("invalid")
    source = "---\nlayout: bullets\n---\n- One"
    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)

    deck = Markdown.load!(path)

    assert {:error, message} =
             Editor.save(deck, hd(deck.slides), "---\nlayout bullets\n---\n- One")

    assert message =~ "invalid slide frontmatter"
    assert File.read!(path) == source
  end

  test "rejects decks without source location metadata" do
    deck = %Deck{title: "Manual", slides: []}
    slide = %Slide{title: "Manual", source: "# Manual"}

    assert {:error, "Slide source is not editable"} = Editor.save(deck, slide, "# Edited")
  end

  defp temp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "easy-breezy-editor-#{label}-#{System.unique_integer([:positive])}.md"
    )
  end
end
