defmodule EasyBreezy.Markdown do
  @moduledoc false

  alias EasyBreezy.Layouts.CodeSlide

  @code "\e[36m"

  def render(doc, width, opts \\ []) when is_binary(doc) do
    reset = Keyword.get(opts, :reset, IO.ANSI.reset())
    width = max(width, 1)

    doc
    |> String.split(["\r\n", "\n"], trim: false)
    |> Enum.map(&String.trim_trailing/1)
    |> markdown_blocks()
    |> render_blocks(width, opts, reset)
  end

  def render_bullet(text, width, opts \\ []) do
    reset = Keyword.get(opts, :reset, IO.ANSI.reset())

    text
    |> markdown_bullet_source()
    |> String.split(["\r\n", "\n"], trim: false)
    |> render_list_block(max(width, 1), reset)
  end

  def ends_with_code_fence?(doc) when is_binary(doc) do
    last_block =
      doc
      |> String.split(["\r\n", "\n"], trim: false)
      |> Enum.map(&String.trim_trailing/1)
      |> markdown_blocks()
      |> List.last()

    match?({:code_fence, _lines}, last_block)
  end

  def starts_with_code_fence?(doc) when is_binary(doc) do
    first_block =
      doc
      |> String.split(["\r\n", "\n"], trim: false)
      |> Enum.map(&String.trim_trailing/1)
      |> markdown_blocks()
      |> List.first()

    match?({:code_fence, _lines}, first_block)
  end

  defp markdown_blocks(lines), do: markdown_blocks(lines, [], [])

  defp markdown_blocks([], current, blocks) do
    current
    |> flush_markdown_block(blocks)
    |> Enum.reverse()
  end

  defp markdown_blocks(["```" <> _ = line | rest], current, blocks) do
    {code_lines, rest} = collect_code_fence(rest, [line])

    markdown_blocks(rest, [], [
      {:code_fence, Enum.reverse(code_lines)} | flush_markdown_block(current, blocks)
    ])
  end

  defp markdown_blocks([line | rest] = lines, current, blocks) do
    if root_bullet_line?(line) do
      {list_lines, rest} = collect_list_block(lines, [])

      markdown_blocks(rest, [], [
        {:list, Enum.reverse(list_lines)} | flush_markdown_block(current, blocks)
      ])
    else
      markdown_blocks(rest, [line | current], blocks)
    end
  end

  defp flush_markdown_block([], blocks), do: blocks

  defp flush_markdown_block(lines, blocks) do
    content =
      lines
      |> Enum.reverse()
      |> Enum.join("\n")
      |> String.trim()

    if content == "" do
      blocks
    else
      [{:markdown, content} | blocks]
    end
  end

  defp collect_code_fence([], lines), do: {lines, []}

  defp collect_code_fence(["```" <> _ = line | rest], lines), do: {[line | lines], rest}

  defp collect_code_fence([line | rest], lines), do: collect_code_fence(rest, [line | lines])

  defp collect_list_block([], lines), do: {lines, []}

  defp collect_list_block([line | rest], lines) do
    if bullet_line?(line) do
      collect_list_block(rest, [line | lines])
    else
      {lines, [line | rest]}
    end
  end

  defp render_block({:markdown, content}, width, _opts, reset) do
    Breeze.Markdown.render(content, width, reset: reset)
  end

  defp render_block({:code_fence, lines}, width, opts, reset) do
    language = code_fence_language(lines)
    content_lines = code_fence_content_lines(lines)

    content_lines
    |> highlight_code_fence_lines(language, width, opts)
    |> Enum.map(&code_line(&1, width, opts, reset))
    |> Enum.join("\n")
  end

  defp render_block({:list, lines}, width, _opts, reset),
    do: render_list_block(lines, width, reset)

  defp render_blocks(blocks, width, opts, reset) do
    blocks
    |> Enum.map(fn block -> {block_type(block), render_block(block, width, opts, reset)} end)
    |> Enum.reject(fn {_type, rendered} -> rendered == "" end)
    |> join_rendered_blocks()
  end

  defp join_rendered_blocks([]), do: ""

  defp join_rendered_blocks([{type, rendered} | rest]) do
    {content, _type} =
      Enum.reduce(rest, {rendered, type}, fn {next_type, next_rendered}, {content, type} ->
        {content <> block_separator(type, next_type) <> next_rendered, next_type}
      end)

    content
  end

  defp block_type({type, _value}), do: type

  defp block_separator(:code_fence, :code_fence), do: "\n\n\n"
  defp block_separator(_previous, _next), do: "\n\n"

  defp code_fence_content_lines([_opening | rest]) do
    case Enum.reverse(rest) do
      [closing | reversed_content] ->
        if code_fence_line?(closing) do
          Enum.reverse(reversed_content)
        else
          rest
        end

      [] ->
        []
    end
  end

  defp code_fence_content_lines([]), do: []

  defp code_fence_language([opening | _rest]) do
    case Regex.run(~r/^```\s*([a-zA-Z0-9_+.-]+)/, String.trim_leading(opening)) do
      [_match, language] -> String.downcase(language)
      _other -> nil
    end
  end

  defp code_fence_language(_lines), do: nil

  defp code_fence_line?(line), do: line |> String.trim_leading() |> String.starts_with?("```")

  defp highlight_code_fence_lines(lines, language, width, opts)
       when language in ["elixir", "ex", "exs"] do
    lines
    |> Enum.join("\n")
    |> CodeSlide.highlight_source_lines(
      "elixir",
      Keyword.get(opts, :code_theme, "github_dark"),
      Keyword.get(opts, :theme_colors, %{}),
      background: Keyword.get(opts, :code_background, :panel),
      width: width
    )
  end

  defp highlight_code_fence_lines(lines, _language, _width, _opts), do: lines

  defp code_line(line, width, opts, reset) do
    code_reset = code_reset(opts)

    line =
      if String.contains?(line, "\e[") do
        code_reset <> line
      else
        code_reset <> @code <> line
      end

    padding_width = max(width - visible_width(line), 0)
    padding = code_reset <> String.duplicate(" ", padding_width)

    line <> padding <> reset
  end

  defp code_reset(opts) do
    opts
    |> Keyword.get(:theme_colors, %{})
    |> ansi_reset(
      Keyword.get(opts, :code_background, :panel),
      Keyword.get(opts, :code_foreground, :text)
    )
  end

  defp ansi_reset(theme_colors, background, foreground) when is_map(theme_colors) do
    case {Map.get(theme_colors, background), Map.get(theme_colors, foreground)} do
      {{br, bg, bb}, {fr, fg, fb}} -> "\e[48;2;#{br};#{bg};#{bb};38;2;#{fr};#{fg};#{fb}m"
      {{br, bg, bb}, _foreground} -> "\e[48;2;#{br};#{bg};#{bb}m"
      {_background, {fr, fg, fb}} -> "\e[38;2;#{fr};#{fg};#{fb}m"
      _other -> ""
    end
  end

  defp ansi_reset(_theme_colors, _background, _foreground), do: ""

  defp visible_width(content) do
    content
    |> String.replace(~r/\e\[[0-9;]*m/, "")
    |> String.length()
  end

  defp render_list_block(lines, width, reset) do
    bullets = Enum.map(lines, &parse_bullet_line/1)

    if Enum.all?(bullets, &match?({:ok, _indent, _item}, &1)) do
      base_indent =
        bullets
        |> Enum.map(fn {:ok, indent, _item} -> indent end)
        |> Enum.min(fn -> 0 end)

      bullets
      |> Enum.map(fn {:ok, indent, item} ->
        indent = max(indent - base_indent, 0)

        item
        |> markdown_bullet_source()
        |> Breeze.Markdown.render(max(width - indent, 1), reset: reset)
        |> indent_lines(indent)
      end)
      |> Enum.join("\n")
    else
      Breeze.Markdown.render(Enum.join(lines, "\n"), width, reset: reset)
    end
  end

  defp root_bullet_line?(line) do
    case parse_bullet_line(line) do
      {:ok, indent, _item} -> indent < 4
      :error -> false
    end
  end

  defp bullet_line?(line), do: match?({:ok, _indent, _item}, parse_bullet_line(line))

  defp markdown_bullet_source(text) do
    text = to_string(text)
    trimmed = String.trim_leading(text)

    if String.match?(trimmed, ~r/^[-*+]\s+/) do
      trimmed
    else
      "- " <> text
    end
  end

  defp parse_bullet_line(line) do
    case Regex.run(~r/^([ \t]*)([-*+])\s+(.+)$/, line) do
      [_match, indent, _marker, item] -> {:ok, indent_width(indent), item}
      _ -> :error
    end
  end

  defp indent_lines(text, 0), do: text

  defp indent_lines(text, indent) do
    padding = String.duplicate(" ", indent)

    text
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &(padding <> &1))
  end

  defp indent_width(indent) do
    indent
    |> String.replace("\t", "  ")
    |> String.length()
  end
end
