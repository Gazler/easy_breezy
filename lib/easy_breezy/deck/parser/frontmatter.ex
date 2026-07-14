defmodule EasyBreezy.Deck.Parser.Frontmatter do
  @moduledoc false

  import NimbleParsec

  newline = choice([string("\r\n"), string("\n")])
  horizontal_space = ascii_string([?\s, ?\t], min: 0)

  key =
    ascii_string([?a..?z, ?A..?Z, ?0..?9, ?_, ?-], min: 1)

  value =
    repeat(lookahead_not(newline) |> utf8_char([]))
    |> reduce({List, :to_string, []})

  entry =
    ignore(horizontal_space)
    |> concat(key)
    |> ignore(horizontal_space)
    |> ignore(string(":"))
    |> ignore(horizontal_space)
    |> concat(value)
    |> ignore(optional(newline))
    |> tag(:entry)

  comment =
    ignore(horizontal_space)
    |> ignore(string("#"))
    |> ignore(value)
    |> ignore(optional(newline))

  blank =
    ignore(horizontal_space)
    |> ignore(newline)

  defparsec(:frontmatter, repeat(choice([entry, comment, blank])) |> eos())
end
