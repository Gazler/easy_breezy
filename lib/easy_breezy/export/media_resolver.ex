defmodule EasyBreezy.Export.MediaResolver do
  @moduledoc false

  alias EasyBreezy.Export.Media
  alias EasyBreezy.Slideshow.KittyImage

  def resolve(decorations) when is_list(decorations) do
    decorations
    |> Enum.flat_map(&decoration_media/1)
  end

  defp decoration_media(%{
         mod: KittyImage,
         state: %{active?: true, mode: "show", path: path} = state,
         layout: layout
       })
       when is_binary(path) and is_map(layout) do
    inset = non_negative_integer(Map.get(state, :inset), 0)

    with {:ok, data} <- File.read(path),
         {:ok, mime_type} <- image_mime_type(data, path) do
      [
        %Media{
          x: max(Map.get(layout, :left, 0) + inset, 0),
          y: max(Map.get(layout, :top, 0) + inset, 0),
          width: max(Map.get(layout, :width, 1) - inset * 2, 1),
          height: max(Map.get(layout, :height, 1) - inset * 2, 1),
          mime_type: mime_type,
          data: data,
          source: Path.expand(path),
          alt: Path.basename(path)
        }
      ]
    else
      _error -> []
    end
  end

  defp decoration_media(_decoration), do: []

  defp image_mime_type(<<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>>, _path),
    do: {:ok, "image/png"}

  defp image_mime_type(<<"GIF87a", _rest::binary>>, _path), do: {:ok, "image/gif"}
  defp image_mime_type(<<"GIF89a", _rest::binary>>, _path), do: {:ok, "image/gif"}
  defp image_mime_type(<<255, 216, 255, _rest::binary>>, _path), do: {:ok, "image/jpeg"}

  defp image_mime_type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>, _path),
    do: {:ok, "image/webp"}

  defp image_mime_type(data, path) do
    case {Path.extname(path) |> String.downcase(), String.trim_leading(data)} do
      {".svg", <<"<svg", _rest::binary>>} -> {:ok, "image/svg+xml"}
      _other -> {:error, :unsupported_image}
    end
  end

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default
end
