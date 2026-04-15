defmodule EasyBreezy.Layouts.Helpers do
  @moduledoc false

  def bullet_line(text, width) do
    wrapped_lines =
      text
      |> String.split()
      |> wrap_words(max(width - 2, 8))

    case wrapped_lines do
      [] -> "•"
      [first | rest] -> Enum.join(["• " <> first | Enum.map(rest, &("  " <> &1))], "\n")
    end
  end

  def wrap_code_line("", _width), do: [""]

  def wrap_code_line(line, width) do
    line
    |> String.graphemes()
    |> Enum.chunk_every(max(width, 1))
    |> Enum.map(&Enum.join/1)
  end

  def wrap_words([], _width), do: []

  def wrap_words(words, width) do
    {lines, current} =
      Enum.reduce(words, {[], ""}, fn word, {lines, current} ->
        cond do
          current == "" -> {lines, word}
          String.length(current <> " " <> word) <= width -> {lines, current <> " " <> word}
          true -> {[current | lines], word}
        end
      end)

    Enum.reverse([current | lines])
  end
end
