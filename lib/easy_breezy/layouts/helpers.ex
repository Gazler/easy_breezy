defmodule EasyBreezy.Layouts.Helpers do
  @moduledoc false

  def bullet_line(text, width, render_context \\ %{}, opts \\ []) do
    reset =
      markdown_reset(
        render_context,
        Keyword.get(opts, :background, :surface),
        Keyword.get(opts, :foreground, :text)
      )

    EasyBreezy.Markdown.render_bullet(text, max(width, 1), reset: reset)
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

  defp markdown_reset(%{theme_colors: theme_colors}, background, foreground) do
    theme_colors
    |> Map.get(background)
    |> ansi_reset(Map.get(theme_colors, foreground))
  end

  defp markdown_reset(_render_context, _background, _foreground), do: IO.ANSI.reset()

  defp ansi_reset({br, bg, bb}, {fr, fg, fb}) do
    "\e[48;2;#{br};#{bg};#{bb};38;2;#{fr};#{fg};#{fb}m"
  end

  defp ansi_reset(background, foreground)
       when is_integer(background) and is_integer(foreground) do
    "\e[#{ansi_background(background)};#{ansi_foreground(foreground)}m"
  end

  defp ansi_reset(_background, {fr, fg, fb}), do: "\e[38;2;#{fr};#{fg};#{fb}m"

  defp ansi_reset(_background, foreground) when is_integer(foreground),
    do: "\e[#{ansi_foreground(foreground)}m"

  defp ansi_reset(_background, _foreground), do: IO.ANSI.reset()

  defp ansi_foreground(color) when color in 0..7, do: 30 + color
  defp ansi_foreground(color) when color in 8..15, do: 90 + color - 8
  defp ansi_foreground(color), do: "38;5;#{color}"

  defp ansi_background(color) when color in 0..7, do: 40 + color
  defp ansi_background(color) when color in 8..15, do: 100 + color - 8
  defp ansi_background(color), do: "48;5;#{color}"
end
