defmodule EasyBreezy.Implicit.TextShimmer do
  @moduledoc false

  @tick_ms 60
  @phase_count 48
  @pause_ms 1_000
  @pause_frames div(@pause_ms + @tick_ms - 1, @tick_ms)

  def init(_children, root_attrs, last_state) do
    started_at_ms =
      Map.get(last_state, :started_at_ms) ||
        System.monotonic_time(:millisecond)

    state =
      last_state
      |> Map.put(:theme_colors, attr(root_attrs, :shimmer_theme_colors, %{}))
      |> Map.put(:background, attr(root_attrs, :shimmer_background, nil))
      |> Map.put(:source, attr(root_attrs, :shimmer_source, nil))
      |> Map.put(:base, attr(root_attrs, :shimmer_base, nil))
      |> Map.put(:highlight, attr(root_attrs, :shimmer_highlight, nil))
      |> Map.put(:frozen_now, frozen_now(root_attrs))
      |> Map.put(:started_at_ms, started_at_ms)

    {:ok, state, animation_options(state)}
  end

  def handle_modifiers(_type, _flags, _state), do: []

  def animate(:root, box, _flags, state, %{layout: %Breeze.Viewport{} = layout} = ctx) do
    content = shimmer_content(box, state, shimmer_frame(state, ctx))

    if content == box.content do
      box
    else
      {:ok, box, overlays: line_overlays(content, layout)}
    end
  end

  def animate(:root, box, _flags, state, ctx) do
    content = shimmer_content(box, state, shimmer_frame(state, ctx))

    if content == box.content do
      box
    else
      %{box | content: content}
    end
  end

  def animate(:child, box, _flags, _state, _ctx), do: box

  def elapsed_frame(started_at_ms, now)
      when is_integer(started_at_ms) and is_integer(now) do
    now
    |> Kernel.-(started_at_ms)
    |> max(0)
    |> div(@tick_ms)
  end

  def elapsed_frame(_started_at_ms, _now), do: 0

  defp shimmer_content(box, state, frame) do
    with {:ok, base} <- resolve_color(state.base, state.theme_colors),
         {:ok, highlight} <- resolve_color(state.highlight, state.theme_colors) do
      source = if is_binary(state.source), do: state.source, else: box.content
      EasyBreezy.Typography.shimmer(source, base, highlight, state.background, phase(frame))
    else
      _ -> box.content
    end
  end

  defp shimmer_frame(%{frozen_now: now} = state, _ctx) when is_integer(now) do
    elapsed_state_frame(state, now)
  end

  defp shimmer_frame(state, %{now: now}) when is_integer(now) do
    elapsed_state_frame(state, now)
  end

  defp shimmer_frame(_state, %{frame: frame}) when is_integer(frame), do: frame
  defp shimmer_frame(_state, _ctx), do: 0

  defp elapsed_state_frame(%{started_at_ms: started_at_ms}, now)
       when is_integer(started_at_ms) and is_integer(now) do
    elapsed_frame(started_at_ms, now)
  end

  defp elapsed_state_frame(_state, _now), do: 0

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

  defp animation_options(%{frozen_now: value}) when is_integer(value), do: []
  defp animation_options(_state), do: [rerender_every: @tick_ms]

  defp frozen_now(root_attrs) do
    case attr(root_attrs, :animation_frozen_now, nil) ||
           attr(root_attrs, :shimmer_frozen_now, nil) do
      value when is_integer(value) -> value
      _other -> nil
    end
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
