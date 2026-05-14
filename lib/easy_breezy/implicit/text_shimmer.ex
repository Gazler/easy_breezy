defmodule EasyBreezy.Implicit.TextShimmer do
  @moduledoc false

  @tick_ms 60
  @phase_count 48
  @pause_ms 1_000
  @pause_frames div(@pause_ms + @tick_ms - 1, @tick_ms)

  def init(_children, root_attrs, last_state) do
    state =
      last_state
      |> Map.put(:theme_colors, attr(root_attrs, :shimmer_theme_colors, %{}))
      |> Map.put(:background, attr(root_attrs, :shimmer_background, nil))
      |> Map.put(:source, attr(root_attrs, :shimmer_source, nil))
      |> Map.put(:base, attr(root_attrs, :shimmer_base, nil))
      |> Map.put(:highlight, attr(root_attrs, :shimmer_highlight, nil))

    {:ok, state, rerender_every: @tick_ms}
  end

  def handle_modifiers(_type, _flags, _state), do: []

  def animate(:root, box, _flags, state, %{frame: frame, layout: %Breeze.Viewport{} = layout}) do
    content = shimmer_content(box, state, frame)

    if content == box.content do
      box
    else
      {:ok, box, overlays: line_overlays(content, layout)}
    end
  end

  def animate(:root, box, _flags, state, %{frame: frame}) do
    content = shimmer_content(box, state, frame)

    if content == box.content do
      box
    else
      %{box | content: content}
    end
  end

  def animate(:child, box, _flags, _state, _ctx), do: box

  defp shimmer_content(box, state, frame) do
    with {:ok, base} <- resolve_color(state.base, state.theme_colors),
         {:ok, highlight} <- resolve_color(state.highlight, state.theme_colors) do
      source = if is_binary(state.source), do: state.source, else: box.content
      EasyBreezy.Typography.shimmer(source, base, highlight, state.background, phase(frame))
    else
      _ -> box.content
    end
  end

  defp phase(frame) do
    step = rem(frame, @phase_count + @pause_frames)

    if step < @phase_count do
      step / @phase_count
    else
      1.0
    end
  end

  defp resolve_color(name, theme_colors) when is_binary(name) do
    case name do
      "primary" -> fetch_theme_color(theme_colors, :primary)
      "secondary" -> fetch_theme_color(theme_colors, :secondary)
      "accent" -> fetch_theme_color(theme_colors, :accent)
      "muted" -> fetch_theme_color(theme_colors, :muted)
      "text" -> fetch_theme_color(theme_colors, :text)
      "panel" -> fetch_theme_color(theme_colors, :panel)
      "bg" -> fetch_theme_color(theme_colors, :bg)
      "stroke" -> fetch_theme_color(theme_colors, :stroke)
      "#" <> _ = hex -> hex_to_rgb(hex)
      _ -> {:error, :unknown_color}
    end
  end

  defp resolve_color({red, green, blue} = color, _theme_colors)
       when red in 0..255 and green in 0..255 and blue in 0..255,
       do: {:ok, color}

  defp resolve_color(_color, _theme_colors), do: {:error, :invalid_color}

  defp fetch_theme_color(theme_colors, key) do
    case Map.get(theme_colors, key) do
      {red, green, blue} = color when red in 0..255 and green in 0..255 and blue in 0..255 ->
        {:ok, color}

      _ ->
        {:error, :missing_theme_color}
    end
  end

  defp hex_to_rgb("#" <> hex) when byte_size(hex) == 6 do
    with {red, ""} <- Integer.parse(binary_part(hex, 0, 2), 16),
         {green, ""} <- Integer.parse(binary_part(hex, 2, 2), 16),
         {blue, ""} <- Integer.parse(binary_part(hex, 4, 2), 16) do
      {:ok, {red, green, blue}}
    else
      _ -> {:error, :invalid_hex}
    end
  end

  defp hex_to_rgb(_hex), do: {:error, :invalid_hex}

  defp attr(attrs, key, default) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end

  defp line_overlays(content, %Breeze.Viewport{left: left, top: top}) do
    content
    |> String.split("\n", trim: false)
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      %{
        x: left,
        y: top + index,
        content: line <> Termite.Style.reset_code(),
        patch_only: true,
        no_wrap: true
      }
    end)
  end
end
