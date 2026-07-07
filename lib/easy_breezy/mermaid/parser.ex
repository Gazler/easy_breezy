defmodule EasyBreezy.Mermaid.Parser do
  @moduledoc false

  import NimbleParsec

  horizontal_space = ascii_string([?\s, ?\t], min: 1)
  optional_horizontal_space = ascii_string([?\s, ?\t], min: 0)
  newline = choice([string("\r\n"), string("\n")])

  direction =
    choice([
      string("TD"),
      string("TB"),
      string("BT"),
      string("LR"),
      string("RL")
    ])

  header_statement =
    choice([string("flowchart"), string("graph")])
    |> optional(ignore(horizontal_space) |> unwrap_and_tag(direction, :direction))
    |> ignore(optional_horizontal_space)

  identifier =
    ascii_char([?A..?Z, ?a..?z])
    |> repeat(ascii_char([?A..?Z, ?a..?z, ?0..?9, ?_, ?-]))
    |> reduce({List, :to_string, []})

  id =
    identifier
    |> unwrap_and_tag(:id)

  quoted_label =
    ignore(string("\""))
    |> repeat(lookahead_not(string("\"")) |> utf8_char([]))
    |> ignore(string("\""))
    |> reduce({List, :to_string, []})

  square_label =
    ignore(string("["))
    |> repeat(lookahead_not(string("]")) |> utf8_char([]))
    |> ignore(string("]"))
    |> reduce({List, :to_string, []})

  round_label =
    ignore(string("("))
    |> repeat(lookahead_not(string(")")) |> utf8_char([]))
    |> ignore(string(")"))
    |> reduce({List, :to_string, []})

  diamond_label =
    ignore(string("{"))
    |> repeat(lookahead_not(string("}")) |> utf8_char([]))
    |> ignore(string("}"))
    |> reduce({List, :to_string, []})

  class_suffix =
    ignore(string(":::"))
    |> unwrap_and_tag(identifier, :class_name)

  node_ref =
    choice([
      id
      |> unwrap_and_tag(square_label, :label)
      |> optional(class_suffix)
      |> tag(:box),
      id
      |> unwrap_and_tag(round_label, :label)
      |> optional(class_suffix)
      |> tag(:round),
      id
      |> unwrap_and_tag(diamond_label, :label)
      |> optional(class_suffix)
      |> tag(:diamond),
      id
      |> optional(class_suffix)
      |> tag(:box)
    ])

  edge_label =
    ignore(string("|"))
    |> choice([
      quoted_label,
      repeat(lookahead_not(string("|")) |> utf8_char([])) |> reduce({List, :to_string, []})
    ])
    |> unwrap_and_tag(:label)
    |> ignore(string("|"))

  node_statement = unwrap_and_tag(node_ref, :node)

  hex_color =
    ignore(string("#"))
    |> times(ascii_char([?0..?9, ?A..?F, ?a..?f]), 6)
    |> reduce({List, :to_string, []})

  class_def_statement =
    ignore(string("classDef"))
    |> ignore(horizontal_space)
    |> unwrap_and_tag(identifier, :name)
    |> ignore(horizontal_space)
    |> ignore(string("color:"))
    |> unwrap_and_tag(hex_color, :color)
    |> tag(:class_def)

  edge_statement =
    unwrap_and_tag(node_ref, :from)
    |> ignore(optional_horizontal_space)
    |> ignore(string("--"))
    |> ignore(string(">"))
    |> optional(edge_label)
    |> ignore(optional_horizontal_space)
    |> unwrap_and_tag(node_ref, :to)
    |> tag(:edge)

  statement =
    choice([
      class_def_statement,
      edge_statement,
      node_statement
    ])
    |> ignore(optional_horizontal_space)

  blank_line =
    ignore(optional_horizontal_space)
    |> ignore(newline)

  comment_line =
    ignore(optional_horizontal_space)
    |> ignore(string("%%"))
    |> ignore(repeat(lookahead_not(newline) |> utf8_char([])))
    |> optional(ignore(newline))

  ignored_line = choice([blank_line, comment_line])

  document =
    repeat(ignored_line)
    |> ignore(optional_horizontal_space)
    |> concat(header_statement)
    |> ignore(optional(newline))
    |> repeat(
      choice([
        ignored_line,
        ignore(optional_horizontal_space)
        |> unwrap_and_tag(statement, :statement)
        |> optional(ignore(newline))
      ])
    )
    |> ignore(optional_horizontal_space)
    |> eos()

  defparsec(:document, document)

  def parse_document(source) when is_binary(source) do
    if String.trim(source) == "" do
      {:error, :empty}
    else
      do_parse_document(source)
    end
  end

  defp do_parse_document(source) do
    with {:ok, tokens} <- parse(source, :document) do
      {:ok,
       %{
         direction: document_direction(tokens),
         statements: document_statements(tokens)
       }}
    end
  end

  defp document_direction(tokens) do
    tokens
    |> Enum.find_value("TD", fn
      {:direction, direction} -> direction
      _token -> nil
    end)
    |> normalize_direction()
  end

  defp normalize_direction(direction) when direction in ["LR", "RL"], do: :lr
  defp normalize_direction(_direction), do: :td

  defp document_statements(tokens) do
    for {:statement, statement} <- tokens, do: statement
  end

  defp parse(source, parser) do
    case apply(__MODULE__, parser, [source]) do
      {:ok, parsed, "", _context, _line, _offset} -> {:ok, parsed}
      {:ok, _parsed, rest, _context, _line, _offset} -> {:error, {:trailing, rest}}
      {:error, reason, rest, _context, _line, _offset} -> {:error, {reason, rest}}
    end
  end
end
