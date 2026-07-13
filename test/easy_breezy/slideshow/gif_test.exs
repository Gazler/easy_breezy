defmodule EasyBreezy.Slideshow.GifTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Slideshow.Gif

  @two_frame_gif Base.decode64!(
                   "R0lGODlhAgABAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQABQAAACwAAAAAAgABAAACAgQKACH5BAAKAAAALAAAAAACAAEAgAAA/wAAAAICBAoAOw=="
                 )

  test "decodes animated GIF frames, delays, and loop metadata to PNG" do
    assert {:ok,
            %{
              width: 2,
              height: 1,
              loop_count: 0,
              frames: [first, second]
            }} = Gif.decode(@two_frame_gif)

    assert first.delay_ms == 50
    assert second.delay_ms == 100
    assert png?(first.png)
    assert png?(second.png)
    assert rgba_pixels(first.png) == <<255, 0, 0, 255, 255, 0, 0, 255>>
    assert rgba_pixels(second.png) == <<0, 0, 255, 255, 0, 0, 255, 255>>

    assert {0, ^first} = Gif.frame_at(%{frames: [first, second], loop_count: 0}, 49)
    assert {1, ^second} = Gif.frame_at(%{frames: [first, second], loop_count: 0}, 50)
    assert {0, ^first} = Gif.frame_at(%{frames: [first, second], loop_count: 0}, 150)
  end

  test "rejects malformed GIF data" do
    assert {:error, _reason} = Gif.decode("GIF89a-not-a-gif")
  end

  defp png?(<<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>>), do: true
  defp png?(_data), do: false

  defp rgba_pixels(png) do
    chunks = png |> binary_part(8, byte_size(png) - 8) |> png_chunks([])
    compressed = chunks |> Keyword.get_values(:IDAT) |> IO.iodata_to_binary()
    <<0, pixels::binary>> = :zlib.uncompress(compressed)
    pixels
  end

  defp png_chunks(<<>>, chunks), do: Enum.reverse(chunks)

  defp png_chunks(
         <<length::unsigned-big-integer-size(32), type::binary-size(4), data::binary-size(length),
           _crc::binary-size(4), rest::binary>>,
         chunks
       ) do
    png_chunks(rest, [{String.to_atom(type), data} | chunks])
  end
end
