defmodule EasyBreezy.DeckMarkdownTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Deck.Markdown
  alias EasyBreezy.{Deck, Slide}

  defmodule CounterView do
    use Breeze.View

    def render(assigns), do: ~H"<box>Counter</box>"
  end

  test "parses deck and slide frontmatter into structs" do
    assert %Deck{
             title: "Breeze",
             slides: [
               %Slide{
                 id: :intro,
                 title: "Intro",
                 layout: :title,
                 payload: %{
                   title: "Intro",
                   prefix: "Chapter 1",
                   subtitle: "Terminal slides",
                   speaker: "Gazler",
                   footer: "Built on Breeze"
                 },
                 steps: 0
               },
               %Slide{
                 title: "Why",
                 layout: :bullets,
                 payload: %{items: ["One", "Two"]},
                 steps: 1
               }
             ]
           } =
             Markdown.parse!("""
             ---
             title: Breeze
             ---
             ---
             id: intro
             layout: title
             title: Intro
             prefix: Chapter 1
             subtitle: Terminal slides
             speaker: Gazler
             footer: Built on Breeze
             ---
             <!-- Speaker note -->
             ---
             layout: bullets
             title: Why
             ---
             - One
             - Two
             """)
  end

  test "parses code slides with focus ranges" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :code,
                 payload: payload,
                 steps: 2
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: code
             title: Snippet
             language: elixir
             focus: [1..2, 4]
             ---
             IO.puts(:ok)
             """)

    assert %{
             code_language: "elixir",
             code_source: "IO.puts(:ok)",
             code_focus_ranges: []
           } = payload.(80, 0)

    assert %{code_focus_ranges: [{1, 2}]} = payload.(80, 1)
    assert %{code_focus_ranges: [4]} = payload.(80, 2)
  end

  test "keeps plain markdown slides available" do
    assert %Deck{
             title: "Plain",
             slides: [
               %Slide{
                 layout: :markdown,
                 payload: %{
                   markdown: "# Plain\n\nBody text",
                   markdown_blocks: [%{type: :markdown, content: "# Plain\n\nBody text"}]
                 }
               }
             ]
           } = Markdown.parse!("# Plain\n\nBody text")
  end

  test "preserves markdown before slide separators" do
    assert %Deck{
             slides: [
               %Slide{title: "One", payload: %{markdown: "# One"}},
               %Slide{title: "Two", payload: %{markdown: "# Two"}}
             ]
           } =
             Markdown.parse!("""
             # One
             ---
             # Two
             """)
  end

  test "uses inferred titles in slide payloads" do
    assert %Deck{
             slides: [
               %Slide{
                 title: "Why",
                 layout: :bullets,
                 payload: %{title: "Why", items: ["One", "Two"]}
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: bullets
             ---
             # Why

             - One
             - Two
             """)
  end

  test "keeps trailing markdown for bullet slides" do
    assert %Deck{
             slides: [
               %Slide{
                 title: "Why",
                 layout: :bullets,
                 payload: %{
                   title: "Why",
                   items: ["One", "Two"],
                   after_markdown: "Final **note** with `code`."
                 },
                 steps: 2
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: bullets
             title: Why
             ---
             - One
             - Two

             Final **note** with `code`.
             """)
  end

  test "parses mermaid fences inside markdown slides" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :markdown,
                 payload: %{
                   markdown_blocks: [
                     %{type: :markdown, content: "# Flow\n\nBefore"},
                     %{
                       type: :mermaid,
                       content: "flowchart TD\n  Breeze --> BackBreeze"
                     },
                     %{type: :markdown, content: "After"}
                   ]
                 }
               }
             ]
           } =
             Markdown.parse!("""
             # Flow

             Before

             ```mermaid
             flowchart TD
               Breeze --> BackBreeze
             ```

             After
             """)
  end

  test "parses split slots and markdown images" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :two_column,
                 payload: %{
                   left_title: "Runtime pieces",
                   left_items: ["A Breeze.View owns state.", "Breeze.Server handles IO."],
                   right_title: "Preview",
                   right_mode: :image,
                   right_path: right_path
                 },
                 steps: 1,
                 disable_transitions?: true
               }
             ]
           } =
             Markdown.parse!(
               """
               ---
               layout: two-cols
               title: Anatomy
               ---
               # Runtime pieces

               - A Breeze.View owns state.
               - Breeze.Server handles IO.

               ::right::

               # Preview

               ![Screenshot](image.png)
               """,
               base_path: "/tmp/deck"
             )

    assert right_path == "/tmp/deck/image.png"
  end

  test "resolves two-column metadata image paths against the deck directory" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :two_column,
                 payload: %{
                   right_mode: :image,
                   right_path: right_path
                 },
                 disable_transitions?: true
               }
             ]
           } =
             Markdown.parse!(
               """
               ---
               layout: two-column
               title: Diagram
               right_mode: image
               right_path: image.png
               ---
               # Notes
               """,
               base_path: "/tmp/deck"
             )

    assert right_path == "/tmp/deck/image.png"
  end

  test "parses breeze slides with view modules" do
    assert %Deck{
             slides: [
               %Slide{
                 title: "Counter Demo",
                 layout: :breeze,
                 payload: %{
                   title: "Counter Demo",
                   view: CounterView,
                   start_opts: [],
                   assigns: %{},
                   breeze_class: "width-full height-full"
                 },
                 disable_transitions?: true
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: breeze
             title: Counter Demo
             view: EasyBreezy.DeckMarkdownTest.CounterView
             disable-transitions: true
             ---
             """)
  end

  test "allows punctuation in values and hyphenated keys" do
    assert %Deck{
             slides: [
               %Slide{
                 title: "Why Markdown?",
                 disable_transitions?: true
               }
             ]
           } =
             Markdown.parse!("""
             ---
             title: Why Markdown?
             disable-transitions: true
             ---
             Body
             """)
  end
end
