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
