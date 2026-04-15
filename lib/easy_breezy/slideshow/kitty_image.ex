defmodule EasyBreezy.Slideshow.KittyImage do
  @moduledoc false

  @image_id 991_337
  @placement_id 1
  @offset_x 1
  @offset_y 2

  def init(_children, root_attrs, last_state) do
    path = Map.get(root_attrs, :"image-path")
    active? = truthy?(Map.get(root_attrs, :"image-active", false))
    mode = Map.get(root_attrs, :"image-mode", "show")

    state =
      last_state
      |> Map.merge(%{
        path: path,
        active?: active?,
        mode: mode,
        command: build_command(path)
      })

    {:ok, state, rerender_every: 1_000}
  end

  def handle_event(_, _, state), do: {:noreply, state}
  def handle_modifiers(:root, _flags, _state), do: []
  def handle_modifiers(:child, _flags, _state), do: []

  def animate(
        :root,
        box,
        _flags,
        %{active?: true, mode: "show", command: command},
        %{layout: layout}
      )
      when is_map(layout) and is_binary(command) do
    overlay = %{x: layout.left + @offset_x, y: layout.top + @offset_y, content: command}
    {:ok, box, overlays: [overlay]}
  end

  def animate(:root, box, _flags, %{active?: true, mode: "delete", path: path}, _ctx)
      when is_binary(path) do
    overlay = %{x: 0, y: 0, content: delete_command()}
    {:ok, box, overlays: [overlay]}
  end

  def animate(:root, box, _flags, _state, _ctx), do: box
  def animate(:child, box, _flags, _state, _ctx), do: box

  defp build_command(nil), do: nil

  defp build_command(path) do
    with {:ok, image} <- File.read(path) do
      rows = 12
      columns = 30
      chunks = chunk_base64(Base.encode64(image))
      last_index = length(chunks) - 1

      chunks
      |> Enum.with_index()
      |> Enum.map_join(fn {chunk, index} ->
        metadata =
          if index == 0 do
            "a=T,f=100,i=#{@image_id},p=#{@placement_id},q=2,C=1,c=#{columns},r=#{rows},m=#{more?(index, last_index)};"
          else
            "m=#{more?(index, last_index)};"
          end

        "\e_G" <> metadata <> chunk <> "\e\\"
      end)
    else
      _ -> nil
    end
  end

  defp more?(index, last_index), do: if(index < last_index, do: 1, else: 0)

  defp chunk_base64(data) do
    data
    |> String.to_charlist()
    |> Enum.chunk_every(4096)
    |> Enum.map(&List.to_string/1)
  end

  def delete_command do
    "\e_Ga=d,d=I,i=#{@image_id},q=2\e\\"
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
