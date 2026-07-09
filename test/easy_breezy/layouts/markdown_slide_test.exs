defmodule EasyBreezy.Layouts.MarkdownSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.Deck.Markdown

  test "markdown slide scroll area fills the available body height" do
    deck =
      Markdown.parse!("""
      ---
      title: Markdown Deck
      ---
      ---
      id: markdown
      layout: markdown
      title: Plain Markdown
      ---
      # Plain Markdown

      This slide renders with `Breeze.Markdown`.

      - Headings
      - Paragraphs
      - Bullet lists

      ```mermaid
      flowchart TD
        Markdown --> Mermaid
        Mermaid --> Terminal
      ```
      """)

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {84, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    rendered =
      session
      |> Breeze.Test.render!()
      |> strip_ansi()

    assert rendered =~ "│ Terminal │"
    assert rendered =~ "└──────────┘"
    refute rendered =~ "▲"
    refute rendered =~ "█"
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")
end
