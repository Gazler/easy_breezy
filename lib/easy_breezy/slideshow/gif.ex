defmodule EasyBreezy.Slideshow.Gif do
  @moduledoc false

  import Bitwise

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @default_delay_ms 40
  @max_canvas_pixels 16_777_216
  @max_animation_pixels 33_554_432
  @max_frames 256
  @default_graphics_control %{delay_ms: @default_delay_ms, disposal: 0, transparent: nil}

  def decode(data) when is_binary(data) do
    decode_data(data)
  end

  def decode(_data), do: {:error, :invalid_gif}

  def frame_at(%{frames: [_ | _] = frames, loop_count: loop_count}, elapsed_ms)
      when is_integer(elapsed_ms) do
    total_duration = Enum.sum(Enum.map(frames, & &1.delay_ms))
    elapsed_ms = max(elapsed_ms, 0)

    animation_time =
      case loop_count do
        0 -> rem(elapsed_ms, total_duration)
        nil -> min(elapsed_ms, total_duration - 1)
        count -> min(elapsed_ms, total_duration * (count + 1) - 1) |> rem(total_duration)
      end

    frame_for_time(frames, animation_time, 0)
  end

  defp decode_data(
         <<signature::binary-size(6), width::little-unsigned-integer-size(16),
           height::little-unsigned-integer-size(16), packed, background_index, _aspect,
           rest::binary>>
       )
       when signature in ["GIF87a", "GIF89a"] and width > 0 and height > 0 and
              width * height <= @max_canvas_pixels do
    global_table? = (packed &&& 0x80) != 0
    color_count = 1 <<< ((packed &&& 0x07) + 1)

    with {:ok, palette, rest} <- read_palette(rest, global_table?, color_count) do
      background = palette_color(palette, background_index, 255)

      parse_blocks(rest, %{
        width: width,
        height: height,
        global_palette: palette,
        background: background,
        background_index: background_index,
        canvas: :binary.copy(background, width * height),
        graphics_control: @default_graphics_control,
        frames: [],
        frame_count: 0,
        loop_count: nil
      })
    end
  rescue
    _error -> {:error, :invalid_gif}
  end

  defp decode_data(_data), do: {:error, :invalid_gif}

  defp frame_for_time([frame | _frames], elapsed_ms, index)
       when elapsed_ms < frame.delay_ms,
       do: {index, frame}

  defp frame_for_time([frame | frames], elapsed_ms, index),
    do: frame_for_time(frames, elapsed_ms - frame.delay_ms, index + 1)

  defp parse_blocks(<<0x3B, _rest::binary>>, %{frames: []}), do: {:error, :no_frames}

  defp parse_blocks(<<0x3B, _rest::binary>>, state) do
    {:ok,
     %{
       width: state.width,
       height: state.height,
       frames: Enum.reverse(state.frames),
       loop_count: state.loop_count
     }}
  end

  defp parse_blocks(
         <<0x21, 0xF9, 4, packed, delay::little-unsigned-integer-size(16), transparent, 0,
           rest::binary>>,
         state
       ) do
    graphics_control = %{
      delay_ms: frame_delay(delay),
      disposal: packed >>> 2 &&& 0x07,
      transparent: if((packed &&& 0x01) != 0, do: transparent)
    }

    parse_blocks(rest, %{state | graphics_control: graphics_control})
  end

  defp parse_blocks(<<0x21, 0xFF, size, rest::binary>>, state) do
    with {:ok, application, rest} <- take(rest, size),
         {:ok, data, rest} <- read_sub_blocks(rest) do
      loop_count = application_loop_count(application, data, state.loop_count)
      parse_blocks(rest, %{state | loop_count: loop_count})
    end
  end

  defp parse_blocks(<<0x21, _label, rest::binary>>, state) do
    with {:ok, _data, rest} <- read_sub_blocks(rest) do
      parse_blocks(rest, state)
    end
  end

  defp parse_blocks(<<0x2C, rest::binary>>, state) do
    with {:ok, frame, rest} <- read_image(rest, state) do
      parse_blocks(rest, frame)
    end
  end

  defp parse_blocks(<<_unknown, rest::binary>>, state), do: parse_blocks(rest, state)
  defp parse_blocks(<<>>, _state), do: {:error, :unexpected_end}

  defp read_image(
         <<left::little-unsigned-integer-size(16), top::little-unsigned-integer-size(16),
           width::little-unsigned-integer-size(16), height::little-unsigned-integer-size(16),
           packed, rest::binary>>,
         state
       )
       when width > 0 and height > 0 and left + width <= state.width and
              top + height <= state.height and state.frame_count < @max_frames and
              (state.frame_count + 1) * state.width * state.height <= @max_animation_pixels do
    local_table? = (packed &&& 0x80) != 0
    interlaced? = (packed &&& 0x40) != 0
    color_count = 1 <<< ((packed &&& 0x07) + 1)

    with {:ok, local_palette, rest} <- read_palette(rest, local_table?, color_count),
         <<minimum_code_size, rest::binary>> <- rest,
         {:ok, compressed, rest} <- read_sub_blocks(rest),
         {:ok, indices} <- lzw_decode(compressed, minimum_code_size),
         {:ok, indices} <- frame_indices(indices, width, height, interlaced?) do
      palette = if(local_table?, do: local_palette, else: state.global_palette)
      control = state.graphics_control
      previous_canvas = first_frame_canvas(state, control)

      canvas =
        compose_frame(
          previous_canvas,
          indices,
          palette,
          control.transparent,
          state.width,
          state.height,
          left,
          top,
          width,
          height
        )

      frame = %{png: png(canvas, state.width, state.height), delay_ms: control.delay_ms}

      next_canvas =
        disposed_canvas(
          control.disposal,
          previous_canvas,
          canvas,
          state,
          control,
          left,
          top,
          width,
          height
        )

      {:ok,
       %{
         state
         | canvas: next_canvas,
           frames: [frame | state.frames],
           frame_count: state.frame_count + 1,
           graphics_control: @default_graphics_control
       }, rest}
    else
      _error -> {:error, :invalid_image}
    end
  end

  defp read_image(_data, _state), do: {:error, :invalid_image}

  defp first_frame_canvas(%{frames: [], canvas: canvas, background_index: index}, %{
         transparent: index
       }) do
    :binary.copy(<<0, 0, 0, 0>>, div(byte_size(canvas), 4))
  end

  defp first_frame_canvas(state, _control), do: state.canvas

  defp disposed_canvas(3, previous, _canvas, _state, _control, _l, _t, _w, _h),
    do: previous

  defp disposed_canvas(2, _previous, canvas, state, control, left, top, width, height) do
    background =
      if control.transparent == state.background_index,
        do: <<0, 0, 0, 0>>,
        else: state.background

    fill_rectangle(canvas, background, state.width, state.height, left, top, width, height)
  end

  defp disposed_canvas(_disposal, _previous, canvas, _state, _control, _l, _t, _w, _h),
    do: canvas

  defp compose_frame(
         canvas,
         indices,
         palette,
         transparent,
         canvas_width,
         canvas_height,
         left,
         top,
         width,
         height
       ) do
    row_bytes = canvas_width * 4

    0..(canvas_height - 1)
    |> Enum.map(fn row ->
      old_row = binary_part(canvas, row * row_bytes, row_bytes)

      if row >= top and row < top + height do
        frame_row = row - top
        frame_indices = binary_part(indices, frame_row * width, width)
        prefix_size = left * 4
        segment_size = width * 4
        prefix = binary_part(old_row, 0, prefix_size)
        old_segment = binary_part(old_row, prefix_size, segment_size)

        suffix =
          binary_part(old_row, prefix_size + segment_size, row_bytes - prefix_size - segment_size)

        [prefix, compose_row(frame_indices, old_segment, palette, transparent), suffix]
      else
        old_row
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp compose_row(indices, old_pixels, palette, transparent) do
    compose_row(indices, old_pixels, palette, transparent, [])
  end

  defp compose_row(<<>>, <<>>, _palette, _transparent, pixels) do
    pixels |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp compose_row(
         <<index, indices::binary>>,
         <<old::binary-size(4), old_pixels::binary>>,
         palette,
         transparent,
         pixels
       ) do
    pixel = if index == transparent, do: old, else: palette_color(palette, index, 255)
    compose_row(indices, old_pixels, palette, transparent, [pixel | pixels])
  end

  defp fill_rectangle(canvas, color, canvas_width, canvas_height, left, top, width, height) do
    row_bytes = canvas_width * 4
    fill = :binary.copy(color, width)

    0..(canvas_height - 1)
    |> Enum.map(fn row ->
      old_row = binary_part(canvas, row * row_bytes, row_bytes)

      if row >= top and row < top + height do
        prefix_size = left * 4
        segment_size = width * 4
        prefix = binary_part(old_row, 0, prefix_size)

        suffix =
          binary_part(old_row, prefix_size + segment_size, row_bytes - prefix_size - segment_size)

        [prefix, fill, suffix]
      else
        old_row
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp frame_indices(indices, width, height, false) do
    expected = width * height

    if byte_size(indices) >= expected,
      do: {:ok, binary_part(indices, 0, expected)},
      else: {:error, :short_frame}
  end

  defp frame_indices(indices, width, height, true) do
    with {:ok, indices} <- frame_indices(indices, width, height, false) do
      rows = for <<row::binary-size(^width) <- indices>>, do: row
      order = interlace_order(height)
      rows_by_output_line = order |> Enum.zip(rows) |> Map.new()

      {:ok,
       0..(height - 1)
       |> Enum.map(&Map.fetch!(rows_by_output_line, &1))
       |> IO.iodata_to_binary()}
    end
  end

  defp interlace_order(height) do
    [{0, 8}, {4, 8}, {2, 4}, {1, 2}]
    |> Enum.flat_map(fn {start, step} ->
      if start < height do
        Stream.iterate(start, &(&1 + step)) |> Enum.take_while(&(&1 < height))
      else
        []
      end
    end)
  end

  defp lzw_decode(data, minimum_code_size) when minimum_code_size in 1..8 do
    clear_code = 1 <<< minimum_code_size
    end_code = clear_code + 1

    lzw_codes(
      data,
      0,
      minimum_code_size + 1,
      base_dictionary(clear_code),
      end_code + 1,
      clear_code,
      end_code,
      nil,
      []
    )
  end

  defp lzw_decode(_data, _minimum_code_size), do: {:error, :invalid_code_size}

  defp lzw_codes(
         data,
         offset,
         code_size,
         dictionary,
         next_code,
         clear_code,
         end_code,
         previous,
         output
       ) do
    case read_code(data, offset, code_size) do
      :eof ->
        {:error, :missing_end_code}

      {^clear_code, offset} ->
        lzw_codes(
          data,
          offset,
          initial_code_size(clear_code),
          base_dictionary(clear_code),
          end_code + 1,
          clear_code,
          end_code,
          nil,
          output
        )

      {^end_code, _offset} ->
        {:ok, output |> Enum.reverse() |> IO.iodata_to_binary()}

      {code, offset} ->
        case dictionary_entry(dictionary, code, next_code, previous) do
          {:ok, entry} ->
            {dictionary, next_code, code_size} =
              extend_dictionary(dictionary, next_code, code_size, previous, entry)

            lzw_codes(
              data,
              offset,
              code_size,
              dictionary,
              next_code,
              clear_code,
              end_code,
              entry,
              [entry | output]
            )

          :error ->
            {:error, :invalid_lzw_code}
        end
    end
  end

  defp dictionary_entry(dictionary, code, _next_code, _previous)
       when is_map_key(dictionary, code),
       do: {:ok, Map.fetch!(dictionary, code)}

  defp dictionary_entry(_dictionary, code, code, previous) when is_binary(previous),
    do: {:ok, previous <> binary_part(previous, 0, 1)}

  defp dictionary_entry(_dictionary, _code, _next_code, _previous), do: :error

  defp extend_dictionary(dictionary, next_code, code_size, nil, _entry),
    do: {dictionary, next_code, code_size}

  defp extend_dictionary(dictionary, next_code, code_size, previous, entry)
       when next_code < 4096 do
    dictionary = Map.put(dictionary, next_code, previous <> binary_part(entry, 0, 1))
    next_code = next_code + 1

    code_size =
      if next_code == 1 <<< code_size and code_size < 12, do: code_size + 1, else: code_size

    {dictionary, next_code, code_size}
  end

  defp extend_dictionary(dictionary, next_code, code_size, _previous, _entry),
    do: {dictionary, next_code, code_size}

  defp read_code(data, offset, size) when offset + size <= byte_size(data) * 8 do
    byte_offset = div(offset, 8)
    bit_offset = rem(offset, 8)
    bytes = div(bit_offset + size + 7, 8)
    value = data |> binary_part(byte_offset, bytes) |> :binary.decode_unsigned(:little)
    {value >>> bit_offset &&& (1 <<< size) - 1, offset + size}
  end

  defp read_code(_data, _offset, _size), do: :eof

  defp initial_code_size(clear_code), do: bit_width(clear_code) + 1
  defp bit_width(number), do: number |> Integer.digits(2) |> length() |> Kernel.-(1)

  defp base_dictionary(clear_code) do
    Map.new(0..(clear_code - 1), fn index -> {index, <<index>>} end)
  end

  defp read_palette(rest, false, _color_count), do: {:ok, {}, rest}

  defp read_palette(rest, true, color_count) do
    with {:ok, data, rest} <- take(rest, color_count * 3) do
      palette = for <<red, green, blue <- data>>, do: {red, green, blue}
      {:ok, List.to_tuple(palette), rest}
    end
  end

  defp palette_color(palette, index, alpha)
       when is_tuple(palette) and index >= 0 and index < tuple_size(palette) do
    {red, green, blue} = elem(palette, index)
    <<red, green, blue, alpha>>
  end

  defp palette_color(_palette, _index, alpha), do: <<0, 0, 0, alpha>>

  defp read_sub_blocks(data), do: read_sub_blocks(data, [])

  defp read_sub_blocks(<<0, rest::binary>>, blocks),
    do: {:ok, blocks |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp read_sub_blocks(<<size, rest::binary>>, blocks) do
    with {:ok, block, rest} <- take(rest, size) do
      read_sub_blocks(rest, [block | blocks])
    end
  end

  defp read_sub_blocks(<<>>, _blocks), do: {:error, :unexpected_end}

  defp take(data, size) when byte_size(data) >= size do
    <<value::binary-size(^size), rest::binary>> = data
    {:ok, value, rest}
  end

  defp take(_data, _size), do: {:error, :unexpected_end}

  defp application_loop_count(
         "NETSCAPE2.0",
         <<1, loops::little-unsigned-integer-size(16), _::binary>>,
         _current
       ),
       do: loops

  defp application_loop_count(
         "ANIMEXTS1.0",
         <<1, loops::little-unsigned-integer-size(16), _::binary>>,
         _current
       ),
       do: loops

  defp application_loop_count(_application, _data, current), do: current

  defp frame_delay(0), do: @default_delay_ms
  defp frame_delay(delay), do: delay * 10

  defp png(rgba, width, height) do
    scanlines =
      0..(height - 1)
      |> Enum.map(fn row -> [<<0>>, binary_part(rgba, row * width * 4, width * 4)] end)
      |> IO.iodata_to_binary()

    header =
      <<width::unsigned-big-integer-size(32), height::unsigned-big-integer-size(32), 8, 6, 0, 0,
        0>>

    IO.iodata_to_binary([
      @png_signature,
      png_chunk("IHDR", header),
      png_chunk("IDAT", :zlib.compress(scanlines)),
      png_chunk("IEND", <<>>)
    ])
  end

  defp png_chunk(type, data) do
    [
      <<byte_size(data)::unsigned-big-integer-size(32)>>,
      type,
      data,
      <<:erlang.crc32(type <> data)::unsigned-big-integer-size(32)>>
    ]
  end
end
