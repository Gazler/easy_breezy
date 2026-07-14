defmodule EasyBreezy.DeckParserTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Deck.Parser

  test "returns raw frontmatter with source locations" do
    source =
      """
      ---
      layout: code
      steps: 2
      disable-transitions: true
      ---
      IO.puts(:ok)
      """
      |> String.trim_trailing()

    assert %{
             source: ^source,
             entries: [
               %{
                 frontmatter: [
                   %{key: "layout", value: "code"},
                   %{key: "steps", value: "2"},
                   %{key: "disable-transitions", value: "true"}
                 ],
                 body: "IO.puts(:ok)",
                 source: ^source,
                 source_range: {0, source_size}
               }
             ]
           } = Parser.parse!(source)

    assert source_size == byte_size(source)
  end

  test "normalizes newlines before assigning byte ranges" do
    parsed = Parser.parse!("# Same\r\n---\r\n# Same")

    assert parsed.source == "# Same\n---\n# Same"

    assert [
             %{frontmatter: [], source: "# Same", source_range: {0, 6}},
             %{frontmatter: [], source: "# Same", source_range: {11, 6}}
           ] = parsed.entries
  end

  test "preserves duplicate frontmatter entries for later validation" do
    parsed =
      Parser.parse!("""
      ---
      layout: bullets
      layout: code
      ---
      Content
      """)

    assert [%{frontmatter: frontmatter}] = parsed.entries

    assert frontmatter == [
             %{key: "layout", value: "bullets"},
             %{key: "layout", value: "code"}
           ]
  end

  test "reports malformed frontmatter" do
    assert_raise ArgumentError, ~r/invalid slide frontmatter/, fn ->
      Parser.parse!("---\nlayout bullets\n---\nContent")
    end
  end
end
