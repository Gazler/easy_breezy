defmodule EasyBreezy.Slideshow.KittyImage do
  @moduledoc false

  alias EasyBreezy.Slideshow.Gif

  @image_id 991_337
  @placement_id 1
  @default_inset 1
  @columns 30
  @rows 12
  @cache __MODULE__.Cache
  @client_animation_interval_ms 25

  def init(_children, root_attrs, last_state) do
    path = Map.get(root_attrs, :"image-path")
    active? = truthy?(Map.get(root_attrs, :"image-active", false))
    mode = Map.get(root_attrs, :"image-mode", "show")
    scope = Map.get(root_attrs, :"image-scope")
    inset = non_negative_integer(Map.get(root_attrs, :"image-inset"), @default_inset)

    animation_transport =
      animation_transport(path, Map.get(root_attrs, :"image-animation-mode", "auto"))

    animation_started_at_ms =
      if Map.get(last_state, :path) == path do
        Map.get(last_state, :animation_started_at_ms, now_ms())
      else
        now_ms()
      end

    state =
      last_state
      |> Map.merge(%{
        path: path,
        active?: active?,
        mode: mode,
        scope: scope,
        inset: inset,
        animation_transport: animation_transport,
        animation_started_at_ms: animation_started_at_ms
      })

    rerender_every =
      if animation_transport == :client,
        do: @client_animation_interval_ms,
        else: 1_000

    {:ok, state, rerender_every: rerender_every}
  end

  def handle_event(_, _, state), do: {:noreply, state}
  def handle_modifiers(:root, _flags, _state), do: []
  def handle_modifiers(:child, _flags, _state), do: []

  def animate(
        :root,
        box,
        _flags,
        %{
          active?: true,
          mode: "show",
          path: path,
          animation_transport: :client,
          animation_started_at_ms: started_at_ms
        } = state,
        %{layout: layout} = context
      )
      when is_map(layout) and is_binary(path) do
    inset = non_negative_integer(Map.get(state, :inset), @default_inset)
    {columns, rows} = image_dimensions(layout, inset)
    signature = file_signature(path)
    scope = placement_scope(Map.get(state, :scope), Map.get(context, :id))
    image_id = image_id(scope, path, columns, rows, signature)
    placement_id = placement_id(scope, path)
    elapsed_ms = context_now_ms(context) - started_at_ms

    command =
      client_animation_command(
        path,
        signature,
        elapsed_ms,
        columns,
        rows,
        image_id,
        placement_id
      )

    overlay = %{
      x: layout.left + inset,
      y: layout.top + inset,
      width: columns,
      height: rows,
      image_id: image_id,
      placement_id: placement_id,
      patch_only: true,
      content: command
    }

    if is_binary(command),
      do: {:ok, box, overlays: [overlay]},
      else: box
  end

  def animate(
        :root,
        box,
        _flags,
        %{active?: true, mode: "show", path: path} = state,
        %{layout: layout} = context
      )
      when is_map(layout) and is_binary(path) do
    inset = non_negative_integer(Map.get(state, :inset), @default_inset)
    {columns, rows} = image_dimensions(layout, inset)
    signature = file_signature(path)
    scope = placement_scope(Map.get(state, :scope), Map.get(context, :id))
    image_id = image_id(scope, path, columns, rows, signature)
    placement_id = placement_id(scope, path)
    command = build_command(path, columns, rows, image_id, placement_id, signature)

    overlay = %{
      x: layout.left + inset,
      y: layout.top + inset,
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

  defp image_dimensions(%{width: width, height: height}, inset) do
    {
      width |> integer_or(@columns) |> Kernel.-(inset * 2) |> max(1),
      height |> integer_or(@rows) |> Kernel.-(inset * 2) |> max(1)
    }
  end

  defp image_dimensions(_layout, _inset), do: {@columns, @rows}

  defp integer_or(value, _default) when is_integer(value) and value > 0, do: value
  defp integer_or(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default

  defp build_command(path, columns, rows, image_id, placement_id, signature) do
    key = {path, columns, rows, image_id, placement_id, signature}

    case cache_lookup(key) do
      {:ok, command} -> command
      :error -> build_and_cache_command(key, path, columns, rows, image_id, placement_id)
    end
  end

  defp client_animation_command(
         path,
         signature,
         elapsed_ms,
         columns,
         rows,
         image_id,
         placement_id
       ) do
    with {:ok, animation} <- gif_animation(path, signature),
         {frame_index, frame} <- Gif.frame_at(animation, elapsed_ms) do
      key =
        {:client_animation_frame, path, signature, frame_index, columns, rows, image_id,
         placement_id}

      case cache_lookup(key) do
        {:ok, command} ->
          command

        :error ->
          command = static_image_command(frame.png, columns, rows, image_id, placement_id)
          cache_put(key, command)
          command
      end
    else
      _error -> nil
    end
  end

  defp gif_animation(path, signature) do
    key = {:gif_animation, path, signature}

    case cache_lookup(key) do
      {:ok, animation} ->
        {:ok, animation}

      :error ->
        with {:ok, image} <- File.read(path),
             {:ok, animation} <- Gif.decode(image) do
          cache_put(key, animation)
          {:ok, animation}
        end
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

  defp image_command(<<"GIF8", _rest::binary>> = image, columns, rows, image_id, placement_id) do
    case Gif.decode(image) do
      {:ok, animation} -> animation_command(animation, columns, rows, image_id, placement_id)
      {:error, _reason} -> nil
    end
  end

  defp image_command(image, columns, rows, image_id, placement_id) do
    static_image_command(image, columns, rows, image_id, placement_id)
  end

  defp static_image_command(image, columns, rows, image_id, placement_id) do
    metadata =
      "a=T,f=100,i=#{image_id},p=#{placement_id},q=2,C=1,c=#{columns},r=#{rows}"

    [delete_legacy_image_command(), transmit_command(image, metadata, "q=2,")]
    |> IO.iodata_to_binary()
  end

  defp animation_command(
         %{frames: [first_frame], loop_count: _loop_count},
         columns,
         rows,
         image_id,
         placement_id
       ) do
    static_image_command(first_frame.png, columns, rows, image_id, placement_id)
  end

  defp animation_command(
         %{frames: [first_frame | remaining_frames], loop_count: loop_count},
         columns,
         rows,
         image_id,
         placement_id
       ) do
    root_metadata =
      "a=T,f=100,i=#{image_id},p=#{placement_id},q=2,C=1,c=#{columns},r=#{rows}"

    [first_animation_frame | remaining_frames] = remaining_frames

    first_animation_command =
      animation_frame_command(first_animation_frame, image_id)

    remaining_frame_commands =
      Enum.map(remaining_frames, &animation_frame_command(&1, image_id))

    [
      delete_legacy_image_command(),
      transmit_command(first_frame.png, root_metadata, "q=2,"),
      first_animation_command,
      animation_control(image_id, "s=2"),
      remaining_frame_commands,
      animation_control(image_id, "r=1,z=#{first_frame.delay_ms}"),
      animation_control(image_id, "s=3,v=#{kitty_loop_count(loop_count)}")
    ]
    |> IO.iodata_to_binary()
  end

  defp animation_frame_command(frame, image_id) do
    metadata = "a=f,f=100,i=#{image_id},q=2,z=#{frame.delay_ms},X=1"
    transmit_command(frame.png, metadata, "a=f,q=2,")
  end

  defp transmit_command(image, first_metadata, continuation_metadata) do
    chunks = chunk_base64(Base.encode64(image))
    last_index = length(chunks) - 1

    chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      metadata =
        if index == 0,
          do: "#{first_metadata},m=#{more?(index, last_index)};",
          else: "#{continuation_metadata}m=#{more?(index, last_index)};"

      "\e_G" <> metadata <> chunk <> "\e\\"
    end)
  end

  defp animation_control(image_id, controls), do: "\e_Ga=a,i=#{image_id},#{controls}\e\\"

  defp kitty_loop_count(0), do: 1
  defp kitty_loop_count(nil), do: 2
  defp kitty_loop_count(loop_count), do: loop_count + 1

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

  defp animation_transport(path, requested) do
    if gif_path?(path) do
      case requested do
        mode when mode in [:client, "client"] -> :client
        mode when mode in [:terminal, "terminal"] -> :terminal
        _auto -> if(kitty_terminal?(), do: :terminal, else: :client)
      end
    else
      :terminal
    end
  end

  defp gif_path?(path) when is_binary(path),
    do: path |> Path.extname() |> String.downcase() == ".gif"

  defp gif_path?(_path), do: false

  defp kitty_terminal? do
    System.get_env("TERM") == "xterm-kitty" or is_binary(System.get_env("KITTY_WINDOW_ID"))
  end

  defp context_now_ms(%{now_ms: now_ms}) when is_integer(now_ms), do: now_ms
  defp context_now_ms(_context), do: now_ms()
  defp now_ms, do: System.monotonic_time(:millisecond)
end
