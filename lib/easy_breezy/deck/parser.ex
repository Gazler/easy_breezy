defmodule EasyBreezy.Deck.Parser do
  @moduledoc false

  alias EasyBreezy.Deck.Markdown.LineParser
  alias EasyBreezy.Deck.Parser.Frontmatter

  def parse!(source) when is_binary(source) do
    source = normalize_newlines(source)

    %{
      source: source,
      entries: source |> split_entries() |> attach_source_ranges(source)
    }
  end

  defp normalize_newlines(source), do: String.replace(source, "\r\n", "\n")

  defp split_entries(source) do
    {starts_with_delimiter?, chunks} = split_delimited_chunks(source)

    case {starts_with_delimiter?, chunks} do
      {false, [single]} ->
        [%{frontmatter: [], body: single, source: String.trim(single, "\n")}]

      {true, chunks} ->
        pair_frontmatter_entries(chunks)

      {false, chunks} ->
        entries_after_leading_body(chunks)
    end
  end

  defp split_delimited_chunks(source) do
    chunks =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce([[]], fn line, [current | chunks] ->
        if LineParser.delimiter?(line) do
          [[] | [current | chunks]]
        else
          [[line | current] | chunks]
        end
      end)
      |> Enum.reverse()
      |> Enum.map(&lines_to_chunk/1)

    case chunks do
      ["" | rest] -> {true, rest}
      chunks -> {false, chunks}
    end
  end

  defp lines_to_chunk(lines) do
    lines
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp pair_frontmatter_entries(parts) do
    parts
    |> Enum.chunk_every(2, 2, [""])
    |> Enum.map(fn [frontmatter, body] -> frontmatter_entry(frontmatter, body) end)
    |> reject_empty_entries()
  end

  defp entries_after_leading_body([body | parts]) do
    body = String.trim(body, "\n")

    [%{frontmatter: [], body: body, source: body} | entries_after_body(parts)]
    |> reject_empty_entries()
  end

  defp entries_after_body([]), do: []

  defp entries_after_body([body]) do
    body = String.trim(body, "\n")
    [%{frontmatter: [], body: body, source: body}]
  end

  defp entries_after_body([frontmatter, body | rest]) do
    if frontmatter_block?(frontmatter) do
      [frontmatter_entry(frontmatter, body) | entries_after_body(rest)]
    else
      frontmatter = String.trim(frontmatter, "\n")

      [
        %{frontmatter: [], body: frontmatter, source: frontmatter}
        | entries_after_body([body | rest])
      ]
    end
  end

  defp frontmatter_entry(frontmatter, body) do
    body = String.trim(body, "\n")

    %{
      frontmatter: parse_frontmatter!(frontmatter),
      body: body,
      source: frontmatter_source(frontmatter, body)
    }
  end

  defp frontmatter_source(frontmatter, "") do
    "---\n#{String.trim(frontmatter, "\n")}\n---"
  end

  defp frontmatter_source(frontmatter, body) do
    "---\n#{String.trim(frontmatter, "\n")}\n---\n#{body}"
  end

  defp reject_empty_entries(entries) do
    Enum.reject(entries, fn entry -> entry.frontmatter == [] and String.trim(entry.body) == "" end)
  end

  defp attach_source_ranges(entries, source) do
    {entries, _offset} =
      Enum.map_reduce(entries, 0, fn entry, offset ->
        case source_range(source, entry, offset) do
          {start, length} = range -> {Map.put(entry, :source_range, range), start + length}
          nil -> {Map.put(entry, :source_range, nil), offset}
        end
      end)

    entries
  end

  defp source_range(source, %{source: "---\n" <> _rest} = entry, offset) do
    body_size = byte_size(entry.body)
    header_size = byte_size(entry.source) - if(body_size == 0, do: 0, else: body_size + 1)
    header = binary_part(entry.source, 0, header_size)

    with {start, _header_length} <- binary_match(source, header, offset),
         {body_start, body_length} <- body_range(source, entry.body, start + header_size) do
      {start, body_start + body_length - start}
    else
      _other -> nil
    end
  end

  defp source_range(source, %{source: entry_source}, offset) do
    binary_match(source, entry_source, offset)
  end

  defp body_range(_source, "", header_end), do: {header_end, 0}
  defp body_range(source, body, header_end), do: binary_match(source, body, header_end)

  defp binary_match(source, needle, offset) do
    scope_length = byte_size(source) - offset

    case :binary.match(source, needle, scope: {offset, scope_length}) do
      {start, length} -> {start, length}
      :nomatch -> nil
    end
  end

  defp frontmatter_block?(frontmatter) do
    case Frontmatter.frontmatter(frontmatter) do
      {:ok, entries, "", _context, _line, _offset} -> entries != []
      _result -> false
    end
  end

  defp parse_frontmatter!(frontmatter) do
    case Frontmatter.frontmatter(frontmatter) do
      {:ok, entries, "", _context, _line, _offset} ->
        Enum.map(entries, fn {:entry, [key, value]} -> %{key: key, value: value} end)

      {:error, reason, rest, _context, {line, _column}, _offset} ->
        raise ArgumentError,
              "invalid slide frontmatter on line #{line}: #{reason} near #{inspect(rest)}"
    end
  end
end
