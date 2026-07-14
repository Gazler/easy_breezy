defmodule EasyBreezy.DeckValidatorTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Deck.{Parser, Validator}

  test "coerces values and canonicalizes supported aliases" do
    assert %{entries: [%{meta: metadata}]} =
             validate!("""
             ---
             layout: two-cols
             transition: slide-up
             steps: 2
             disable-transitions: true
             speaker: Kept as text
             ---
             Content
             """)

    assert metadata == %{
             layout: :two_column,
             transition: :slide_up,
             steps: 2,
             disable_transitions: true,
             speaker: "Kept as text"
           }
  end

  test "adds defaults to plain markdown slides" do
    assert %{entries: [%{meta: %{layout: :markdown, transition: :slide}}]} =
             validate!("# Plain")
  end

  test "keeps the leading empty entry as deck metadata" do
    assert %{
             entries: [
               %{meta: %{title: "Demo"}, body: ""},
               %{meta: %{layout: :markdown, transition: :slide}}
             ]
           } =
             validate!("""
             ---
             title: Demo
             ---
             ---
             layout: markdown
             ---
             # Slide
             """)
  end

  test "rejects duplicate normalized frontmatter keys" do
    assert_raise ArgumentError, ~r/duplicate frontmatter key `disable_transitions`/, fn ->
      validate!("""
      ---
      disable-transitions: true
      disable_transitions: false
      ---
      Content
      """)
    end
  end

  test "rejects unknown frontmatter keys with entry location" do
    assert_raise ArgumentError,
                 ~r/invalid deck entry 1 on line 1: unsupported frontmatter key `unknown_option`/,
                 fn ->
                   validate!("---\nunknown_option: value\n---\nContent")
                 end
  end

  test "rejects unsupported layouts with entry location" do
    assert_raise ArgumentError,
                 ~r/invalid deck entry 2 on line 4: unsupported layout :unknown/,
                 fn ->
                   validate!("""
                   ---
                   title: Demo
                   ---
                   ---
                   layout: unknown
                   ---
                   Content
                   """)
                 end
  end

  test "rejects unsupported transitions" do
    assert_raise ArgumentError, ~r/unsupported transition :fade/, fn ->
      validate!("---\ntransition: fade\n---\nContent")
    end
  end

  defp validate!(source) do
    source
    |> Parser.parse!()
    |> Validator.validate!()
  end
end
