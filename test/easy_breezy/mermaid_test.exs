defmodule EasyBreezy.MermaidTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.{Deck, Slide}
  alias EasyBreezy.Deck.Markdown
  alias EasyBreezy.Mermaid

  test "renders a simple top-down dependency chain" do
    source = """
    flowchart TD
      breeze[Breeze] --> back_breeze[BackBreeze]
      back_breeze --> termite[Termite]
    """

    assert render_ascii(source) ==
             ascii_snapshot([
               "                                   ┌────────┐",
               "                                   │ Breeze │",
               "                                   └───┬────┘",
               "                                       │",
               "                                 ┌─────▼──────┐",
               "                                 │ BackBreeze │",
               "                                 └─────┬──────┘",
               "                                       │",
               "                                  ┌────▼────┐",
               "                                  │ Termite │",
               "                                  └─────────┘"
             ])
  end

  test "returns a useful error for unsupported syntax" do
    assert {:error, message} = Mermaid.render("sequenceDiagram\nA->>B: hello", 48, 20)

    assert message =~ "Expected Mermaid flowchart or graph header"
  end

  test "parses labels and node shapes without leaking mermaid delimiters" do
    source = """
    flowchart TD
      start(Start) -->|yes| decision{Ready?}
      decision --> done[Done]
    """

    assert {:ok, graph} = Mermaid.parse(source)

    assert graph.edges == [
             %Mermaid.Edge{from: "start", to: "decision", label: "yes"},
             %Mermaid.Edge{from: "decision", to: "done", label: nil}
           ]

    assert graph.nodes["start"].label == "Start"
    assert graph.nodes["start"].shape == :round
    assert graph.nodes["decision"].label == "Ready?"
    assert graph.nodes["decision"].shape == :diamond
    assert graph.nodes["done"].label == "Done"
    refute graph.nodes["done"].label =~ "["
  end

  test "renders rounded and decision nodes as ascii" do
    source = """
    flowchart TD
      start(Start) --> check{Ready?}
      check -->|yes| ship(Ship it)
      check -->|no| revise[Revise]
    """

    assert render_ascii(source) ==
             ascii_snapshot([
               "                                   ╭───────╮",
               "                                   │ Start │",
               "                                   ╰───┬───╯",
               "                                       │",
               "                                  ┌────▼─────┐",
               "                                  │‹ Ready? ›│",
               "                                  └────┬─────┘",
               "                                ┌─yes──┴─no───┐",
               "                           ╭────▼────╮    ┌───▼────┐",
               "                           │ Ship it │    │ Revise │",
               "                           ╰─────────╯    └────────┘"
             ])
  end

  test "aligns single-node top-down layers with mixed node widths" do
    source = """
    flowchart TD
      Markdown --> Mermaid
      Mermaid --> Terminal
    """

    lines = source |> render_ascii() |> String.split("\n")
    first_left = lines |> line_containing("┌──────────┐") |> leading_spaces()
    second_left = lines |> line_containing("┌────▼────┐") |> leading_spaces()
    third_left = lines |> line_containing("┌────▼─────┐") |> leading_spaces()

    assert first_left == second_left
    assert first_left == third_left
  end

  test "parses simple class color definitions" do
    source = """
    graph LR
    classDef examplecolor color:#ff00ff
    A --> ColorText:::examplecolor
    """

    assert {:ok, graph} = Mermaid.parse(source)

    assert graph.class_defs == %{"examplecolor" => %{color: "#ff00ff"}}
    assert graph.nodes["ColorText"].class_name == "examplecolor"

    assert render_ascii(source) == "[A]──▶ [ColorText]"

    assert {:ok, lines} = Mermaid.render(source, 80, 20, truncate?: false, ansi_restore: "<r>")
    assert Enum.join(lines, "\n") =~ "\e[38;2;255;0;255mColorText<r>"
  end

  test "mermaid component stays clipped inside a two-column slide" do
    deck = %Deck{
      title: "Breeze",
      slides: [
        %Slide{
          id: :mermaid,
          title: "Mermaid Component",
          layout: :two_column,
          payload: %{
            title: "Mermaid Component",
            left_title: "Source",
            left_lines: [
              "flowchart TD",
              "  breeze[Breeze] --> back_breeze[BackBreeze]",
              "  back_breeze --> termite[Termite]"
            ],
            right_title: "Terminal render",
            right_mode: :mermaid,
            right_mermaid_source: """
            flowchart TD
              breeze[Breeze] --> back_breeze[BackBreeze]
              back_breeze --> termite[Termite]
            """
          }
        }
      ]
    }

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {78, 21},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    rendered = Breeze.Test.render!(session)

    assert rendered =~ "flowchart TD"
    assert rendered =~ "Breeze"
    assert rendered =~ "BackBreeze"
    assert rendered =~ "Termite"
  end

  test "renders mermaid fences inside markdown slides" do
    deck =
      Markdown.parse!("""
      # Inline Mermaid

      Before

      ```mermaid
      flowchart TD
        Breeze --> BackBreeze
      ```

      After
      """)

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {80, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    raw_rendered = Breeze.Test.render!(session)
    refute raw_rendered =~ IO.ANSI.reset() <> "."

    rendered =
      raw_rendered
      |> BackBreeze.Utils.strip_escape_chars()

    assert rendered =~ "Before"
    assert rendered =~ "Breeze"
    assert rendered =~ "BackBreeze"
    assert rendered =~ "After"
    assert_centered_line(rendered, "┌────────┐")
    refute rendered =~ "flowchart TD"
    refute rendered =~ "```"
  end

  test "keeps inline markdown punctuation styled on system themes" do
    deck = Markdown.parse!("`Breeze.Markdown`.")

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {80, 12},
        theme: Breeze.Theme.default(),
        start_opts: [deck: deck, themes: [:system16], theme: :system16]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    rendered = Breeze.Test.render!(session)

    refute rendered =~ IO.ANSI.reset() <> "."
    assert rendered =~ "\e[100;37m."
  end

  defp render_ascii(source) do
    {:ok, lines} = Mermaid.render(source, 80, 30, truncate?: false, ansi_restore: "")

    lines
    |> Enum.join("\n")
    |> BackBreeze.Utils.strip_escape_chars()
  end

  defp ascii_snapshot(lines), do: Enum.join(lines, "\n")

  defp line_containing(lines, content), do: Enum.find(lines, &String.contains?(&1, content))

  defp leading_spaces(line) do
    ~r/^ */
    |> Regex.run(line)
    |> hd()
    |> String.length()
  end

  defp assert_centered_line(rendered, content) do
    line =
      rendered
      |> String.split("\n")
      |> Enum.find(&String.contains?(&1, content))

    assert line

    inner =
      line
      |> String.trim_leading("│")
      |> String.trim_trailing("│")

    left = leading_spaces(inner)
    right = ~r/ *$/ |> Regex.run(inner) |> hd() |> String.length()

    assert abs(left - right) <= 1
  end
end
