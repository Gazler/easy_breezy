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

  test "markdown slides leave a blank line after the title" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Custom Title
      ---
      Body text
      """)

    rendered = render_plain!(deck, step: 0)
    lines = String.split(rendered, "\n", trim: false)
    title_index = Enum.find_index(lines, &String.contains?(&1, "│Custom Title"))

    assert title_index != nil
    assert blank_slide_line?(Enum.at(lines, title_index + 1))
  end

  test "markdown slides render nested lists" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Nested
      ---
      # Nested Lists

      - Parent
        - Child `code`
          - Grandchild
      - Next
      """)

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {84, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    raw_rendered = Breeze.Test.render!(session)
    rendered = strip_ansi(raw_rendered)

    assert raw_rendered =~ "\e[36mcode"
    assert rendered =~ "• Parent"
    assert rendered =~ "  • Child code"
    assert rendered =~ "    • Grandchild"
    assert rendered =~ "• Next"
    refute rendered =~ "- Child"
  end

  test "markdown slides preserve list and fenced code order" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Termite API
      ---
      - adapter based Terminal library
        - prim_tty (OTP 26 and 27) adapter by default
        - shell (OTP 28) adapter
      - Simple, declarative output API

      ```elixir
      terminal = Termite.Terminal.start()

      str =
        Termite.Style.bold()
        |> Termite.Style.foreground(3)
        |> Termite.Style.background(5)
        |> Termite.Style.render_to_string("Hello World")

      Termite.Terminal.write(terminal, str)
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

    assert_in_order(rendered, [
      "• adapter based Terminal library",
      "  • prim_tty (OTP 26 and 27) adapter by default",
      "  • shell (OTP 28) adapter",
      "• Simple, declarative output API",
      "terminal = Termite.Terminal.start()",
      "str =",
      "Termite.Style.bold()",
      "|> Termite.Style.foreground(3)",
      "|> Termite.Style.background(5)",
      ~S[|> Termite.Style.render_to_string("Hello World")],
      "Termite.Terminal.write(terminal, str)"
    ])
  end

  test "markdown slides highlight elixir fences on a panel background" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Code
      ---
      ```elixir
      terminal = Termite.Terminal.start()
      ```
      """)

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {84, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    rendered = Breeze.Test.render!(session)
    plain = strip_ansi(rendered)

    assert plain =~ "terminal = Termite.Terminal.start()"
    assert rendered =~ "\e[48;2;31;70;98"
    assert rendered =~ "\e[38;2;"
  end

  test "markdown slides render breeze fences" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Custom
      ---
      Before

      ```breeze
      <box style="text-3 bg-5 bold">Hello World</box>
      ```

      After
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

    assert_in_order(rendered, ["Before", "Hello World", "After"])
    refute rendered =~ "<box"
  end

  test "markdown slide breeze fences import typography components" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Typography
      ---
      ```breeze
      <.h2>Type</.h2>
      ```
      """)

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {84, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    rendered = session |> Breeze.Test.render!() |> strip_ansi()

    assert rendered =~ "╺┳╸╻ ╻┏━┓┏━╸"
  end

  test "markdown slides separate code fences from following breeze fences" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Custom
      ---
      ```elixir
      IO.puts(:ok)
      ```
      ```breeze
      <box style="text-3 bg-5 bold">Hello World</box>
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

    assert rendered =~ "│IO.puts(:ok)"
    assert_blank_line_between(rendered, "IO.puts(:ok)", "Hello World")
  end

  test "compact markdown slides keep revealed breeze fences fully visible" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: BackBreeze Example
      ---

      ```elixir
      BackBreeze.Box.new(
        style: %{border: :rounded, padding: 1},
        children: [
          BackBreeze.Box.new(content: "Hello"),
          BackBreeze.Box.new(
            content: "I am red",
            style: %{foreground_color: 1}
          )
        ]
      )
      |> BackBreeze.Box.render()
      ```

      <!-- step -->

      ```breeze
      <box class="border-rounded padding-1 width-12">
        <box>Hello</box>
        <box class="text-1">I am red</box>
      </box>
      ```
      """)

    rendered = render_plain!(deck, step: 1, size: {80, 22})

    assert rendered =~ "|> BackBreeze.Box.render()"
    assert rendered =~ "╭──────────╮"
    assert rendered =~ "╰──────────╯"
  end

  test "markdown step markers reveal later fences on later steps" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Termite API
      ---
      ```elixir
      IO.puts(:ok)
      ```

      <!-- step -->

      ```breeze
      <box style="text-3 bg-5 bold">Hello World</box>
      ```
      """)

    step_0 = render_plain!(deck, step: 0)
    step_1 = render_plain!(deck, step: 1)

    assert step_0 =~ "IO.puts(:ok)"
    refute step_0 =~ "Hello World"

    assert step_1 =~ "IO.puts(:ok)"
    assert_blank_line_between(step_1, "IO.puts(:ok)", "Hello World")
  end

  test "markdown step markers keep space between bullets and later code fences" do
    deck =
      Markdown.parse!("""
      ---
      layout: markdown
      title: Termite API
      ---
      - adapter based Terminal library
      - Simple, declarative output API

      <!-- step -->

      ```elixir
      IO.puts(:ok)
      ```
      """)

    rendered = render_plain!(deck, step: 1)

    assert rendered =~ "• Simple, declarative output API"
    assert_blank_line_between(rendered, "• Simple, declarative output API", "IO.puts(:ok)")
  end

  defp render_plain!(deck, opts) do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: Keyword.get(opts, :size, {84, 24}),
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: deck,
          themes: [:nebula],
          theme: :nebula,
          step: Keyword.get(opts, :step, 0)
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    session
    |> Breeze.Test.render!()
    |> strip_ansi()
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")

  defp blank_slide_line?(line) when is_binary(line) do
    line
    |> String.replace("│", "")
    |> String.trim()
    |> Kernel.==("")
  end

  defp blank_slide_line?(_line), do: false

  defp assert_blank_line_between(text, before_fragment, after_fragment) do
    lines = String.split(text, "\n", trim: false)
    before_index = Enum.find_index(lines, &String.contains?(&1, before_fragment))
    after_index = Enum.find_index(lines, &String.contains?(&1, after_fragment))

    assert before_index != nil
    assert after_index != nil
    assert after_index == before_index + 2
  end

  defp assert_in_order(text, fragments) do
    {_text, _offset} =
      Enum.reduce(fragments, {text, 0}, fn fragment, {remaining, offset} ->
        case :binary.match(remaining, fragment) do
          :nomatch ->
            flunk("expected #{inspect(fragment)} after byte #{offset}")

          {start, length} ->
            next_offset = start + length

            {
              binary_part(remaining, next_offset, byte_size(remaining) - next_offset),
              offset + next_offset
            }
        end
      end)
  end
end
