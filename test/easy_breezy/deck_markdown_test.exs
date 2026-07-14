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

  test "builds slides from canonicalized validator metadata" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :two_column,
                 transition: :slide_up,
                 disable_transitions?: false
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: split
             transition: slide-up
             hide_transitions: false
             ---
             Left
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

  test "parses speaker notes for code slides" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :code,
                 payload: %{
                   code_source: "IO.puts(:ok)",
                   notes: "Mention the return value"
                 }
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: code
             title: Snippet
             language: elixir
             ---
             IO.puts(:ok)

             <!-- Mention the return value -->
             """)
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

  test "keeps slide markdown source" do
    assert %Deck{
             slides: [
               %Slide{source: "# Plain\n\nBody text"},
               %Slide{
                 source: "---\nlayout: bullets\ntitle: Why\n---\n- One\n- Two"
               }
             ]
           } =
             Markdown.parse!("""
             # Plain

             Body text
             ---
             layout: bullets
             title: Why
             ---
             - One
             - Two
             """)
  end

  test "tracks slide source byte ranges independently of duplicate content" do
    assert %Deck{
             source: "# Same\n---\n# Same",
             slides: [
               %Slide{source: "# Same", source_range: {0, 6}},
               %Slide{source: "# Same", source_range: {11, 6}}
             ]
           } = Markdown.parse!("# Same\n---\n# Same")
  end

  test "tracks source ranges across blank lines around frontmatter" do
    source =
      "---\nlayout: bullets\n---\n\n- One\n\n---\nlayout: markdown\n---\n\n# Two"

    deck = Markdown.parse!(source)

    assert [%Slide{source_range: {start, length}}, %Slide{source_range: {_start, _length}}] =
             deck.slides

    assert binary_part(source, start, length) == "---\nlayout: bullets\n---\n\n- One"
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

  test "parses immediate reveal for bullet slides" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :bullets,
                 payload: %{
                   items: ["One", "Two"],
                   reveal: :immediate,
                   after_markdown: "Final **note**."
                 },
                 steps: 0
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: bullets
             title: Why
             reveal: immediate
             ---
             - One
             - Two

             Final **note**.
             """)
  end

  test "infers extra steps from trailing markdown step markers for immediate bullet slides" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :bullets,
                 payload: %{
                   items: ["One", "Two"],
                   reveal: :immediate,
                   after_markdown: "<!-- step -->\n\nFinal **note**."
                 },
                 steps: 1
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: bullets
             title: Why
             reveal: immediate
             ---
             - One
             - Two

             <!-- step -->

             Final **note**.
             """)
  end

  test "groups nested bullets under their top-level bullet" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :bullets,
                 payload: %{
                   items: [
                     "One\n  - One A\n  - `One B`",
                     "Two"
                   ]
                 },
                 steps: 1
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: bullets
             title: Why
             ---
             - One
               - One A
               - `One B`
             - Two
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

  test "parses breeze fences inside markdown slides" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :markdown,
                 payload: %{
                   markdown_blocks: [
                     %{type: :markdown, content: "# Custom\n\nBefore"},
                     %{
                       type: :breeze,
                       content: ~s(<box style="text-3 bg-5 bold">Hello World</box>)
                     },
                     %{type: :markdown, content: "After"}
                   ]
                 }
               }
             ]
           } =
             Markdown.parse!("""
             # Custom

             Before

             ```breeze
             <box style="text-3 bg-5 bold">Hello World</box>
             ```

             After
             """)
  end

  test "parses markdown step markers as progressive content steps" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :markdown,
                 steps: 1,
                 payload: %{
                   notes: nil,
                   markdown_blocks: [
                     %{type: :markdown, content: "Before", step: 0},
                     %{type: :breeze, content: ~s(<box>Hello World</box>), step: 1}
                   ]
                 }
               }
             ]
           } =
             Markdown.parse!("""
             Before

             <!-- step -->

             ```breeze
             <box>Hello World</box>
             ```
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

  test "parses a full-image slide and resolves its asset path" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :image,
                 payload: %{
                   path: path,
                   alt: "The missing feature",
                   width: 72,
                   height: 36,
                   notes: "Reveal the SSH adapter next"
                 },
                 steps: 0,
                 disable_transitions?: true
               }
             ]
           } =
             Markdown.parse!(
               """
               ---
               layout: image
               title: The missing feature
               width: 72
               height: 36
               ---
               ![Typing kitty](typing-kitty.png)

               <!-- Reveal the SSH adapter next -->
               """,
               base_path: "/tmp/deck"
             )

    assert path == "/tmp/deck/typing-kitty.png"
  end

  test "parses immediate reveal for split slides" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :two_column,
                 payload: %{
                   left_items: ["One", "Two"],
                   reveal: :immediate,
                   right_notice: "Advance"
                 },
                 steps: 0
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: two-cols
             title: Split
             reveal: immediate
             right_notice: Advance
             ---
             # Left

             - One
             - Two

             ::right::

             Notes
             """)
  end

  test "groups nested split bullets under their top-level bullet" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :two_column,
                 payload: %{
                   left_items: [
                     "One\n  - One A",
                     "Two"
                   ]
                 },
                 steps: 1
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: two-cols
             title: Split
             ---
             # Left

             - One
               - One A
             - Two
             """)
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
                   breeze_class: "width-full height-full",
                   notes: "Demonstrate the counter"
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
             <!-- Demonstrate the counter -->
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

  test "accepts hide_transition as a disable transitions alias" do
    assert %Deck{
             slides: [
               %Slide{
                 title: "Snake Demo",
                 disable_transitions?: true
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: breeze
             title: Snake Demo
             view: EasyBreezy.DeckMarkdownTest.CounterView
             hide_transition: true
             ---
             """)
  end

  test "parses sync_live_state for breeze slides" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :breeze,
                 payload: %{
                   sync_live_state: false
                 }
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: breeze
             title: Snake Demo
             view: EasyBreezy.DeckMarkdownTest.CounterView
             sync_live_state: false
             ---
             """)
  end

  test "parses breeze_focus for breeze slides" do
    assert %Deck{
             slides: [
               %Slide{
                 layout: :breeze,
                 payload: %{
                   breeze_focus: "languages"
                 }
               }
             ]
           } =
             Markdown.parse!("""
             ---
             layout: breeze
             title: List Demo
             view: EasyBreezy.DeckMarkdownTest.CounterView
             breeze_focus: languages
             ---
             """)
  end
end
