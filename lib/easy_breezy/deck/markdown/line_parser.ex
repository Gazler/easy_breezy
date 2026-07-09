defmodule EasyBreezy.Deck.Markdown.LineParser do
  @moduledoc false

  import NimbleParsec

  horizontal_space = ascii_string([?\s, ?\t], min: 0)
  slot_name = ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?-], min: 1)

  text =
    repeat(utf8_char([]))
    |> reduce({List, :to_string, []})

  non_empty_text =
    times(utf8_char([]), min: 1)
    |> reduce({List, :to_string, []})

  image_prefix =
    repeat(
      lookahead_not(string("!["))
      |> utf8_char([])
    )
    |> reduce({List, :to_string, []})

  image_alt =
    repeat(
      lookahead_not(string("]("))
      |> utf8_char([])
    )

  image_path =
    times(
      lookahead_not(choice([string(")"), ascii_char([?\s, ?\t])]))
      |> utf8_char([]),
      min: 1
    )
    |> reduce({List, :to_string, []})

  image_title =
    ignore(ascii_string([?\s, ?\t], min: 1))
    |> ignore(
      repeat(
        lookahead_not(string(")"))
        |> utf8_char([])
      )
    )

  mermaid_word =
    ignore(ascii_char([?m, ?M]))
    |> ignore(ascii_char([?e, ?E]))
    |> ignore(ascii_char([?r, ?R]))
    |> ignore(ascii_char([?m, ?M]))
    |> ignore(ascii_char([?a, ?A]))
    |> ignore(ascii_char([?i, ?I]))
    |> ignore(ascii_char([?d, ?D]))

  breeze_word =
    ignore(ascii_char([?b, ?B]))
    |> ignore(ascii_char([?r, ?R]))
    |> ignore(ascii_char([?e, ?E]))
    |> ignore(ascii_char([?e, ?E]))
    |> ignore(ascii_char([?z, ?Z]))
    |> ignore(ascii_char([?e, ?E]))

  defparsec(
    :delimiter,
    ignore(horizontal_space)
    |> ignore(string("---"))
    |> ignore(horizontal_space)
    |> eos()
  )

  defparsec(
    :slot_marker,
    ignore(horizontal_space)
    |> ignore(string("::"))
    |> concat(slot_name)
    |> ignore(string("::"))
    |> ignore(horizontal_space)
    |> eos()
  )

  defparsec(
    :bullet_item,
    ignore(horizontal_space)
    |> ignore(choice([string("-"), string("*"), string("+")]))
    |> ignore(ascii_string([?\s, ?\t], min: 1))
    |> concat(non_empty_text)
    |> eos()
  )

  defparsec(
    :bullet_item_with_indent,
    horizontal_space
    |> ignore(choice([string("-"), string("*"), string("+")]))
    |> ignore(ascii_string([?\s, ?\t], min: 1))
    |> concat(non_empty_text)
    |> eos()
  )

  defparsec(
    :markdown_image,
    image_prefix
    |> ignore(string("!["))
    |> ignore(image_alt)
    |> ignore(string("]("))
    |> concat(image_path)
    |> optional(image_title)
    |> ignore(string(")"))
    |> concat(text)
    |> eos()
  )

  defparsec(
    :code_fence_open,
    ignore(horizontal_space)
    |> ignore(string("```"))
    |> ignore(text)
    |> eos()
  )

  defparsec(
    :mermaid_fence_open,
    ignore(horizontal_space)
    |> ignore(string("```"))
    |> ignore(horizontal_space)
    |> concat(mermaid_word)
    |> optional(
      ignore(ascii_string([?\s, ?\t], min: 1))
      |> ignore(text)
    )
    |> eos()
  )

  defparsec(
    :breeze_fence_open,
    ignore(horizontal_space)
    |> ignore(string("```"))
    |> ignore(horizontal_space)
    |> concat(breeze_word)
    |> optional(
      ignore(ascii_string([?\s, ?\t], min: 1))
      |> ignore(text)
    )
    |> eos()
  )

  defparsec(
    :fence_close,
    ignore(horizontal_space)
    |> ignore(string("```"))
    |> ignore(horizontal_space)
    |> eos()
  )

  def delimiter?(line), do: parsed?(delimiter(line))
  def code_fence_open?(line), do: parsed?(code_fence_open(line))
  def mermaid_fence_open?(line), do: parsed?(mermaid_fence_open(line))
  def breeze_fence_open?(line), do: parsed?(breeze_fence_open(line))
  def fence_close?(line), do: parsed?(fence_close(line))

  def slot(line) do
    case slot_marker(line) do
      {:ok, [name], "", _context, _line, _offset} -> name
      _ -> nil
    end
  end

  def bullet(line) do
    case bullet_with_indent(line) do
      %{item: item} -> item
      nil -> nil
    end
  end

  def bullet_with_indent(line) do
    case bullet_item_with_indent(line) do
      {:ok, [indent, item], "", _context, _line, _offset} ->
        %{indent: indent_width(indent), item: String.trim(item)}

      _ ->
        nil
    end
  end

  def markdown_image_path(line) do
    case markdown_image(line) do
      {:ok, [_prefix, path, _suffix], "", _context, _line, _offset} -> path
      _ -> nil
    end
  end

  def remove_markdown_images(line) do
    case markdown_image(line) do
      {:ok, [prefix, _path, suffix], "", _context, _line, _offset} ->
        prefix <> remove_markdown_images(suffix)

      _ ->
        line
    end
  end

  defp parsed?({:ok, [], "", _context, _line, _offset}), do: true
  defp parsed?(_result), do: false

  defp indent_width(indent) do
    indent
    |> String.replace("\t", "  ")
    |> String.length()
  end
end
