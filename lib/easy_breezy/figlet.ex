defmodule EasyBreezy.Figlet do
  @moduledoc """
  A small FIGlet/TOIlet font parser and renderer.

  It intentionally implements the subset EasyBreezy needs for display text:
  standard ASCII glyph blocks, per-glyph end markers, hardblanks, and plain
  no-smush rendering. Built-in fonts live in `priv/figlet`.
  """

  defstruct [:name, :path, :hardblank, :height, glyphs: %{}]

  @type t :: %__MODULE__{
          name: atom() | String.t() | nil,
          path: String.t() | nil,
          hardblank: String.t(),
          height: pos_integer(),
          glyphs: %{String.t() => [String.t()]}
        }

  @builtin_fonts %{
    ansi_shadow: "ansi_shadow.flf",
    doom: "doom.flf",
    future: "future.tlf",
    js_stick_letters: "js_stick_letters.flf"
  }

  @doc """
  Loads a built-in font, a `%EasyBreezy.Figlet{}` font, or a font file path.
  """
  def load!(%__MODULE__{} = font), do: font

  def load!(name) when is_atom(name) do
    case Map.fetch(@builtin_fonts, name) do
      {:ok, filename} -> load_builtin!(name, filename)
      :error -> raise ArgumentError, "unknown built-in figlet font: #{inspect(name)}"
    end
  end

  def load!(path_or_name) when is_binary(path_or_name) do
    case builtin_font(path_or_name) do
      {key, filename} -> load_builtin!(key, filename)
      nil -> parse_file!(path_or_name)
    end
  end

  @doc """
  Parses FIGlet/TOIlet font contents.
  """
  def parse!(source, opts \\ []) when is_binary(source) do
    [header | lines] = split_lines(source)
    {hardblank, height, comment_lines} = parse_header!(header)

    lines = Enum.drop(lines, comment_lines)
    glyph_line_count = height * 95

    if length(lines) < glyph_line_count do
      raise ArgumentError,
            "figlet font is missing glyph rows: expected at least #{glyph_line_count}, got #{length(lines)}"
    end

    glyphs =
      lines
      |> Enum.take(glyph_line_count)
      |> Enum.chunk_every(height)
      |> Enum.zip(32..126)
      |> Map.new(fn {rows, codepoint} ->
        {<<codepoint::utf8>>, decode_glyph(rows)}
      end)

    %__MODULE__{
      name: Keyword.get(opts, :name),
      path: Keyword.get(opts, :path),
      hardblank: hardblank,
      height: height,
      glyphs: glyphs
    }
  end

  @doc """
  Parses a FIGlet/TOIlet font file.
  """
  def parse_file!(path, opts \\ []) when is_binary(path) do
    path
    |> File.read!()
    |> parse!(Keyword.merge(opts, path: path))
  end

  @doc """
  Renders text using a built-in font, parsed font, or font file path.

  Rendering is deliberately simple: glyphs are concatenated without smushing.
  Pass `trim_vertical: true` to remove all-empty leading/trailing rows.
  """
  def render(text, font_or_name \\ :ansi_shadow, opts \\ []) when is_binary(text) do
    font = load!(font_or_name)

    text
    |> String.split("\n", trim: false)
    |> Enum.map(&render_line(&1, font, opts))
    |> Enum.join("\n")
  end

  defp load_builtin!(key, filename) do
    cache_key = {__MODULE__, :builtin, key}

    case :persistent_term.get(cache_key, nil) do
      nil ->
        path = Path.join(font_dir(), filename)
        font = parse_file!(path, name: key)
        :persistent_term.put(cache_key, font)
        font

      %__MODULE__{} = font ->
        font
    end
  end

  defp font_dir do
    case :code.priv_dir(:easy_breezy) do
      path when is_list(path) -> Path.join(List.to_string(path), "figlet")
      {:error, _reason} -> Path.expand("../../priv/figlet", __DIR__)
    end
  end

  defp builtin_font(name) do
    normalized = normalize_name(name)

    Enum.find(@builtin_fonts, fn {key, _filename} ->
      to_string(key) == normalized
    end)
  end

  defp normalize_name(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace([" ", "-"], "_")
  end

  defp split_lines(source) do
    String.split(source, ~r/\r\n|\n|\r/, trim: false)
  end

  defp parse_header!("flf2a" <> tail), do: parse_header_tail!(tail)
  defp parse_header!("tlf2a" <> tail), do: parse_header_tail!(tail)

  defp parse_header!(header) do
    raise ArgumentError, "invalid figlet font header: #{inspect(header)}"
  end

  defp parse_header_tail!(tail) do
    case String.next_grapheme(tail) do
      {hardblank, fields_text} ->
        fields = String.split(fields_text, ~r/\s+/, trim: true)
        height = integer_field!(fields, 0, "height")
        comment_lines = integer_field!(fields, 4, "comment line count")
        {hardblank, height, comment_lines}

      nil ->
        raise ArgumentError, "invalid figlet font header: missing hardblank"
    end
  end

  defp integer_field!(fields, index, name) do
    with value when is_binary(value) <- Enum.at(fields, index),
         {integer, ""} <- Integer.parse(value) do
      integer
    else
      _ -> raise ArgumentError, "invalid figlet font header: missing #{name}"
    end
  end

  defp decode_glyph(rows) do
    endmark =
      rows
      |> List.first("")
      |> String.last()

    Enum.map(rows, &strip_endmark(&1, endmark))
  end

  defp strip_endmark(row, nil), do: row
  defp strip_endmark(row, endmark), do: String.trim_trailing(row, endmark)

  defp render_line(line, font, opts) do
    letter_spacing = opts |> Keyword.get(:letter_spacing, 0) |> max(0)

    rows =
      line
      |> String.graphemes()
      |> Enum.reduce({List.duplicate("", font.height), true}, fn grapheme, {rows, first?} ->
        glyph = Map.get(font.glyphs, grapheme, fallback_glyph(grapheme, font.height))

        prefix =
          if first? or letter_spacing == 0, do: "", else: String.duplicate(" ", letter_spacing)

        rows =
          Enum.zip_with(rows, glyph, fn row, segment ->
            row <> prefix <> segment
          end)

        {rows, false}
      end)
      |> elem(0)
      |> Enum.map(&String.replace(&1, font.hardblank, " "))

    rows =
      if Keyword.get(opts, :trim_vertical, false) do
        trim_blank_edges(rows)
      else
        rows
      end

    Enum.join(rows, "\n")
  end

  defp fallback_glyph(grapheme, height) do
    List.duplicate(grapheme, height)
  end

  defp trim_blank_edges(rows) do
    rows
    |> Enum.drop_while(&blank_row?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&blank_row?/1)
    |> Enum.reverse()
    |> case do
      [] -> [""]
      trimmed -> trimmed
    end
  end

  defp blank_row?(row), do: String.trim(row) == ""
end
