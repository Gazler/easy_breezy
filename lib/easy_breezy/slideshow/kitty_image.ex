defmodule EasyBreezy.Slideshow.KittyImage do
  @moduledoc false

  @image_id 991_337
  @placement_id 1
  @offset_x 1
  @offset_y 1
  @columns 30
  @rows 12
  @cache __MODULE__.Cache

  def init(_children, root_attrs, last_state) do
    path = Map.get(root_attrs, :"image-path")
    active? = truthy?(Map.get(root_attrs, :"image-active", false))
    mode = Map.get(root_attrs, :"image-mode", "show")
    scope = Map.get(root_attrs, :"image-scope")

    state =
      last_state
      |> Map.merge(%{
        path: path,
        active?: active?,
        mode: mode,
        scope: scope
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
        %{active?: true, mode: "show", path: path} = state,
        %{layout: layout} = context
      )
      when is_map(layout) and is_binary(path) do
    {columns, rows} = image_dimensions(layout)
    signature = file_signature(path)
    scope = placement_scope(Map.get(state, :scope), Map.get(context, :id))
    image_id = image_id(scope, path, columns, rows, signature)
    placement_id = placement_id(scope, path)
    command = build_command(path, columns, rows, image_id, placement_id, signature)

    overlay = %{
      x: layout.left + @offset_x,
      y: layout.top + @offset_y,
      width: columns,
      height: rows,
      image_id: image_id,
      placement_id: placement_id,
      content: command
    }

    if is_binary(command),
      do: {:ok, box, overlays: [overlay]},
      else: box
  end

  def animate(:root, box, _flags, %{active?: true, mode: "delete", path: path}, _ctx)
      when is_binary(path) do
    overlay = %{x: 0, y: 0, content: delete_command()}
    {:ok, box, overlays: [overlay]}
  end

  def animate(:root, box, _flags, _state, _ctx), do: box
  def animate(:child, box, _flags, _state, _ctx), do: box

  defp image_dimensions(%{width: width, height: height}) do
    {
      width |> integer_or(@columns) |> Kernel.-(2) |> max(1),
      height |> integer_or(@rows) |> Kernel.-(2) |> max(1)
    }
  end

  defp image_dimensions(_layout), do: {@columns, @rows}

  defp integer_or(value, _default) when is_integer(value) and value > 0, do: value
  defp integer_or(_value, default), do: default

  defp build_command(path, columns, rows, image_id, placement_id, signature) do
    key = {path, columns, rows, image_id, placement_id, signature}

    case cache_lookup(key) do
      {:ok, command} -> command
      :error -> build_and_cache_command(key, path, columns, rows, image_id, placement_id)
    end
  end

  defp build_and_cache_command(key, path, columns, rows, image_id, placement_id) do
    command =
      with {:ok, image} <- File.read(path) do
        image_command(image, columns, rows, image_id, placement_id)
      else
        _ -> nil
      end

    if is_binary(command), do: cache_put(key, command)
    command
  end

  defp image_command(image, columns, rows, image_id, placement_id) do
    chunks = chunk_base64(Base.encode64(image))
    last_index = length(chunks) - 1

    [
      delete_legacy_image_command(),
      chunks
      |> Enum.with_index()
      |> Enum.map_join(fn {chunk, index} ->
        metadata =
          if index == 0 do
            "a=T,f=100,i=#{image_id},p=#{placement_id},q=2,C=1,c=#{columns},r=#{rows},m=#{more?(index, last_index)};"
          else
            "m=#{more?(index, last_index)};"
          end

        "\e_G" <> metadata <> chunk <> "\e\\"
      end)
    ]
    |> IO.iodata_to_binary()
  end

  defp more?(index, last_index), do: if(index < last_index, do: 1, else: 0)

  defp chunk_base64(data) do
    data
    |> String.to_charlist()
    |> Enum.chunk_every(4096)
    |> Enum.map(&List.to_string/1)
  end

  def delete_command do
    "\e_Ga=d,d=A,q=2\e\\"
  end

  defp delete_legacy_image_command do
    "\e_Ga=d,d=I,i=#{@image_id},q=2\e\\"
  end

  def delete_overlay(%{terminal: %{adapter: nil}} = term), do: term

  def delete_overlay(term) do
    %{term | terminal: Termite.Terminal.write(term.terminal, delete_command())}
  rescue
    _ -> term
  end

  defp file_signature(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> {stat.mtime, stat.size}
      _error -> nil
    end
  end

  defp placement_scope(nil, nil), do: "default"
  defp placement_scope(nil, id), do: id
  defp placement_scope(scope, nil), do: scope
  defp placement_scope(scope, id), do: {scope, id}

  defp image_id(scope, path, columns, rows, signature) do
    @image_id + :erlang.phash2({scope, path, columns, rows, signature}, 100_000_000)
  end

  defp placement_id(scope, path) do
    @placement_id + :erlang.phash2({scope, path}, 100_000_000)
  end

  defp cache_lookup(key) do
    ensure_cache!()

    case :ets.lookup(@cache, key) do
      [{^key, command}] -> {:ok, command}
      _other -> :error
    end
  end

  defp cache_put(key, command) do
    ensure_cache!()
    :ets.insert(@cache, {key, command})
    :ok
  end

  defp ensure_cache! do
    case :ets.whereis(@cache) do
      :undefined ->
        try do
          :ets.new(@cache, [:named_table, :public, :set])
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
