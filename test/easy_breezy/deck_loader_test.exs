defmodule EasyBreezy.DeckLoaderTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Deck
  alias EasyBreezy.Deck.Loader

  test "loads a deck with its absolute source location" do
    path = temp_path("editable.md")
    File.write!(path, "# Editable")
    on_exit(fn -> File.rm(path) end)

    assert %Deck{source_path: source_path, source: "# Editable"} = Loader.load!(path)
    assert source_path == Path.expand(path)
  end

  test "resolves referenced files relative to the deck" do
    directory = temp_directory()
    deck_path = Path.join(directory, "slides.md")
    source_path = Path.join(directory, "example.ex")

    File.mkdir_p!(directory)
    File.write!(source_path, "IO.puts(:loaded)")

    File.write!(deck_path, """
    ---
    layout: code
    code-path: example.ex
    ---
    """)

    on_exit(fn -> File.rm_rf(directory) end)

    assert %Deck{slides: [slide]} = Loader.load!(deck_path)
    assert slide.payload.code_source == "IO.puts(:loaded)"
  end

  test "recognizes supported Markdown extensions" do
    assert Loader.markdown_path?("slides.md")
    assert Loader.markdown_path?("slides.markdown")
    refute Loader.markdown_path?("slides.exs")
    refute Loader.markdown_path?(nil)
  end

  defp temp_path(filename) do
    Path.join(
      System.tmp_dir!(),
      "easy-breezy-loader-#{System.unique_integer([:positive])}-#{filename}"
    )
  end

  defp temp_directory do
    Path.join(
      System.tmp_dir!(),
      "easy-breezy-loader-#{System.unique_integer([:positive])}"
    )
  end
end
