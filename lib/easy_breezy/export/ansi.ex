defmodule EasyBreezy.Export.ANSI do
  @moduledoc """
  Converts a rendered BackBreeze terminal surface into `EasyBreezy.Export.Frame`.

  BackBreeze supplies the composed terminal surface, so this module only needs
  to resolve the SGR style sequences emitted by Termite. It supports standard,
  256-colour and true-colour output.
  """

  alias BackBreeze.Box
  alias EasyBreezy.Export.{Frame, Run, Style}

  @escape 27
  @ansi16_colors {
    {0, 0, 0},
    {205, 49, 49},
    {13, 188, 121},
    {229, 229, 16},
    {36, 114, 200},
    {188, 63, 188},
    {17, 168, 205},
    {229, 229, 229},
    {102, 102, 102},
    {241, 76, 76},
    {35, 209, 139},
    {245, 245, 67},
    {59, 142, 234},
    {214, 112, 214},
    {41, 184, 219},
    {255, 255, 255}
  }

  @type parse_option ::
          {:width, pos_integer()}
          | {:height, pos_integer()}
          | {:media, [EasyBreezy.Export.Media.t()]}
          | {:slide_id, term()}
          | {:title, String.t()}
          | {:slide_index, non_neg_integer()}
          | {:step, non_neg_integer()}
          | {:metadata, map()}

  @doc "Converts a rendered box into a positioned, style-resolved terminal frame."
  @spec parse(map(), [parse_option()]) :: Frame.t()
  def parse(%Box{content: content}, opts) when is_binary(content) and is_list(opts) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    state = %{
      x: 0,
      y: 0,
      style: %Style{},
      runs: [],
      backgrounds: %{}
    }

    state = consume(content, state)

    %Frame{
      width: width,
      height: height,
      background: dominant_background(state.backgrounds),
      slide_id: Keyword.get(opts, :slide_id),
      title: Keyword.get(opts, :title),
      slide_index: Keyword.get(opts, :slide_index, 0),
      step: Keyword.get(opts, :step, 0),
      runs: Enum.reverse(state.runs),
      media: Keyword.get(opts, :media, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp consume(<<>>, state), do: state

  defp consume(<<@escape, ?[, rest::binary>>, state) do
    case :binary.match(rest, "m") do
      {index, 1} ->
        parameters = binary_part(rest, 0, index)
        remaining = binary_part(rest, index + 1, byte_size(rest) - index - 1)
        consume(remaining, %{state | style: apply_sgr(state.style, parameters)})

      :nomatch ->
        state
    end
  end

  defp consume(<<@escape, _command, rest::binary>>, state), do: consume(rest, state)
  defp consume(<<"\r", rest::binary>>, state), do: consume(rest, %{state | x: 0})
  defp consume(<<"\n", rest::binary>>, state), do: consume(rest, %{state | x: 0, y: state.y + 1})

  defp consume(content, state) do
    {text, rest} = take_text(content)
    consume(rest, append_run(state, text))
  end

  defp take_text(content) do
    case :binary.match(content, [<<@escape>>, "\r", "\n"]) do
      {index, _length} ->
        {binary_part(content, 0, index), binary_part(content, index, byte_size(content) - index)}

      :nomatch ->
        {content, <<>>}
    end
  end

  defp append_run(state, ""), do: state

  defp append_run(state, text) do
    cell_width = BackBreeze.Utils.string_length(text)

    run = %Run{
      x: state.x,
      y: state.y,
      width: cell_width,
      text: text,
      style: state.style
    }

    backgrounds =
      case Style.effective_background(state.style) do
        nil -> state.backgrounds
        color -> Map.update(state.backgrounds, color, cell_width, &(&1 + cell_width))
      end

    runs = merge_or_prepend(run, state.runs)
    %{state | x: state.x + cell_width, runs: runs, backgrounds: backgrounds}
  end

  defp merge_or_prepend(
         %Run{x: x, y: y, style: style, text: text, width: width},
         [
           %Run{x: previous_x, y: y, style: style, text: previous_text, width: previous_width} =
             previous
           | rest
         ]
       )
       when previous_x + previous_width == x do
    [%{previous | text: previous_text <> text, width: previous_width + width} | rest]
  end

  defp merge_or_prepend(run, runs), do: [run | runs]

  defp dominant_background(backgrounds) when map_size(backgrounds) == 0, do: nil
  defp dominant_background(backgrounds), do: backgrounds |> Enum.max_by(&elem(&1, 1)) |> elem(0)

  defp apply_sgr(style, parameters) do
    parameters
    |> sgr_parameters()
    |> apply_codes(style)
  end

  defp sgr_parameters(""), do: [0]

  defp sgr_parameters(parameters) do
    parameters
    |> String.split(";", trim: false)
    |> Enum.map(fn
      "" ->
        0

      value ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> -1
        end
    end)
  end

  defp apply_codes([], style), do: style
  defp apply_codes([0 | rest], _style), do: apply_codes(rest, %Style{})
  defp apply_codes([1 | rest], style), do: apply_codes(rest, %{style | bold: true})
  defp apply_codes([2 | rest], style), do: apply_codes(rest, %{style | faint: true})
  defp apply_codes([3 | rest], style), do: apply_codes(rest, %{style | italic: true})
  defp apply_codes([4 | rest], style), do: apply_codes(rest, %{style | underline: true})
  defp apply_codes([5 | rest], style), do: apply_codes(rest, %{style | blink: true})
  defp apply_codes([7 | rest], style), do: apply_codes(rest, %{style | inverse: true})
  defp apply_codes([9 | rest], style), do: apply_codes(rest, %{style | crossed_out: true})

  defp apply_codes([22 | rest], style),
    do: apply_codes(rest, %{style | bold: false, faint: false})

  defp apply_codes([23 | rest], style), do: apply_codes(rest, %{style | italic: false})
  defp apply_codes([24 | rest], style), do: apply_codes(rest, %{style | underline: false})
  defp apply_codes([25 | rest], style), do: apply_codes(rest, %{style | blink: false})
  defp apply_codes([27 | rest], style), do: apply_codes(rest, %{style | inverse: false})
  defp apply_codes([29 | rest], style), do: apply_codes(rest, %{style | crossed_out: false})
  defp apply_codes([39 | rest], style), do: apply_codes(rest, %{style | foreground: nil})
  defp apply_codes([49 | rest], style), do: apply_codes(rest, %{style | background: nil})

  defp apply_codes([38, 2, red, green, blue | rest], style) do
    apply_codes(rest, %{style | foreground: rgb(red, green, blue)})
  end

  defp apply_codes([48, 2, red, green, blue | rest], style) do
    apply_codes(rest, %{style | background: rgb(red, green, blue)})
  end

  defp apply_codes([38, 5, index | rest], style) do
    apply_codes(rest, %{style | foreground: ansi256(index)})
  end

  defp apply_codes([48, 5, index | rest], style) do
    apply_codes(rest, %{style | background: ansi256(index)})
  end

  defp apply_codes([code | rest], style) when code in 30..37 do
    apply_codes(rest, %{style | foreground: ansi16(code - 30)})
  end

  defp apply_codes([code | rest], style) when code in 40..47 do
    apply_codes(rest, %{style | background: ansi16(code - 40)})
  end

  defp apply_codes([code | rest], style) when code in 90..97 do
    apply_codes(rest, %{style | foreground: ansi16(code - 90 + 8)})
  end

  defp apply_codes([code | rest], style) when code in 100..107 do
    apply_codes(rest, %{style | background: ansi16(code - 100 + 8)})
  end

  defp apply_codes([_unknown | rest], style), do: apply_codes(rest, style)

  defp rgb(red, green, blue) do
    {clamp_byte(red), clamp_byte(green), clamp_byte(blue)}
  end

  defp clamp_byte(value) when value < 0, do: 0
  defp clamp_byte(value) when value > 255, do: 255
  defp clamp_byte(value), do: value

  defp ansi16(index) when index in 0..15, do: elem(@ansi16_colors, index)
  defp ansi16(_index), do: nil

  defp ansi256(index) when index in 0..15, do: ansi16(index)

  defp ansi256(index) when index in 16..231 do
    offset = index - 16
    red = div(offset, 36)
    green = div(rem(offset, 36), 6)
    blue = rem(offset, 6)
    values = {0, 95, 135, 175, 215, 255}
    {elem(values, red), elem(values, green), elem(values, blue)}
  end

  defp ansi256(index) when index in 232..255 do
    value = 8 + (index - 232) * 10
    {value, value, value}
  end

  defp ansi256(_index), do: nil
end
