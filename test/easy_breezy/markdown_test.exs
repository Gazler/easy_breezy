defmodule EasyBreezy.MarkdownTest do
  use ExUnit.Case, async: true

  test "adds an extra blank line between adjacent fenced code blocks" do
    rendered =
      EasyBreezy.Markdown.render(
        """
        ```elixir
        one
        ```
        ```elixir
        two
        ```
        """,
        40
      )
      |> strip_ansi()

    rendered_lines =
      rendered
      |> String.split("\n", trim: false)
      |> Enum.map(&String.trim_trailing/1)

    assert rendered_lines == [
             "one",
             "",
             "",
             "two"
           ]
  end

  test "highlights elixir fences with a full-width panel background" do
    rendered =
      EasyBreezy.Markdown.render(
        """
        ```elixir
        terminal = Termite.Terminal.start()
        ```
        """,
        36,
        reset: "\e[48;2;25;53;73;38;2;214;231;255m",
        theme_colors: %{
          panel: {31, 70, 98},
          text: {214, 231, 255}
        },
        code_theme: "cyberdream_dark"
      )

    [line] = String.split(rendered, "\n", trim: false)

    assert rendered =~ "\e[48;2;31;70;98"
    assert rendered =~ "Termite"
    assert rendered =~ "\e[38;2;"
    assert strip_ansi(line) |> String.length() == 36
  end

  test "highlights elixir fences with a full-width system16 panel background" do
    rendered =
      EasyBreezy.Markdown.render(
        """
        ```elixir
        EasyBreezy.run(theme: :system16)
        ```
        """,
        40,
        reset: "\e[100;37m",
        theme_colors: %{panel: 0, surface: 8, text: 7},
        code_theme: "github_dark_dimmed"
      )

    [line] = String.split(rendered, "\n", trim: false)

    assert rendered =~ "\e[40;37m"
    refute rendered =~ ~r/\e\[0m\e\[38/
    assert strip_ansi(line) |> String.length() == 40
  end

  test "renders non-elixir fences full width" do
    rendered =
      EasyBreezy.Markdown.render(
        """
        ```text
        alpha
        ```
        """,
        24,
        reset: "\e[48;2;25;53;73;38;2;214;231;255m",
        theme_colors: %{
          panel: {31, 70, 98},
          text: {214, 231, 255}
        }
      )

    [line] = String.split(rendered, "\n", trim: false)

    assert rendered =~ "\e[48;2;31;70;98"
    assert strip_ansi(line) |> String.length() == 24
  end

  test "renders Breeze markdown spans into the slide ANSI context" do
    reset = "\e[48;2;25;53;73;38;2;214;231;255m"
    rendered = EasyBreezy.Markdown.render("Before `code` after", 30, reset: reset)

    assert strip_ansi(rendered) == "Before code after"
    assert rendered =~ reset
    assert rendered =~ "\e[36mcode"
  end

  test "detects markdown ending with a fenced code block" do
    assert EasyBreezy.Markdown.ends_with_code_fence?("""
           Before

           ```elixir
           IO.puts(:ok)
           ```
           """)

    refute EasyBreezy.Markdown.ends_with_code_fence?("""
           ```elixir
           IO.puts(:ok)
           ```

           After
           """)
  end

  test "detects markdown starting with a fenced code block" do
    assert EasyBreezy.Markdown.starts_with_code_fence?("""
           ```elixir
           IO.puts(:ok)
           ```

           After
           """)

    refute EasyBreezy.Markdown.starts_with_code_fence?("""
           Before

           ```elixir
           IO.puts(:ok)
           ```
           """)
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")
end
