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

    assert String.split(rendered, "\n", trim: false) == [
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
