defmodule EasyBreezy.Implicit.TitleGradient do
  @moduledoc false

  alias Breeze.Theme

  @tick_ms 90
  @phase_count 120

  def init(_children, root_attrs, last_state) do
    started_at_ms =
      Map.get(last_state, :started_at_ms) ||
        System.monotonic_time(:millisecond)

    state =
      last_state
      |> Map.put(:direction, attr(root_attrs, :gradient_direction, "text-gradient-to-r"))
      |> Map.put(:theme_colors, attr(root_attrs, :gradient_theme_colors, %{}))
      |> Map.put(:background, attr(root_attrs, :gradient_background, nil))
      |> Map.put(:source, attr(root_attrs, :gradient_source, nil))
      |> Map.put(:started_at_ms, started_at_ms)

    {:ok, state, rerender_every: @tick_ms}
  end

  def handle_modifiers(_type, _flags, _state), do: []

  def colors(theme_colors, frame) when is_map(theme_colors) and is_integer(frame) do
    primary = Map.get(theme_colors, :primary)
    secondary = Map.get(theme_colors, :secondary)
    accent = Map.get(theme_colors, :accent) || secondary

    with true <- rgb_color?(primary),
         true <- rgb_color?(secondary),
         true <- rgb_color?(accent) do
      phase = rem(frame, @phase_count) / @phase_count

      {:ok, Theme.blend(primary, accent, wave(phase)),
       Theme.blend(secondary, primary, wave(phase + 0.33))}
    else
      _ -> :error
    end
  end

  def colors(_theme_colors, _frame), do: :error

  def elapsed_frame(started_at_ms, now)
      when is_integer(started_at_ms) and is_integer(now) do
    now
    |> Kernel.-(started_at_ms)
    |> max(0)
    |> div(@tick_ms)
  end

  def elapsed_frame(_started_at_ms, _now), do: 0

  def animate(
        :root,
        box,
        _flags,
        state,
        %{phase: :async, layout: %Breeze.Viewport{} = layout} = ctx
      ) do
    with {:ok, from, to} <- gradient_colors(state, ctx) do
      content = if is_binary(state.source), do: state.source, else: box.content

      content =
        EasyBreezy.Typography.gradient(content, state.direction, from, to, state.background)

      {:ok, box, overlays: line_overlays(content, layout)}
    else
      _ -> box
    end
  end

  def animate(:root, box, _flags, state, ctx) do
    with {:ok, from, to} <- gradient_colors(state, ctx) do
      content = if is_binary(state.source), do: state.source, else: box.content

      content =
        EasyBreezy.Typography.gradient(content, state.direction, from, to, state.background)

      %{box | content: content}
    else
      _ -> box
    end
  end

  def animate(:child, box, _flags, _state, _ctx), do: box

  defp gradient_colors(%{theme_colors: theme_colors} = state, ctx) when is_map(theme_colors) do
    colors(theme_colors, gradient_frame(state, ctx))
  end

  defp gradient_colors(_state, _ctx), do: :error

  defp gradient_frame(state, %{now: now}) when is_integer(now) do
    elapsed_state_frame(state, now)
  end

  defp gradient_frame(_state, %{frame: frame}) when is_integer(frame), do: frame
  defp gradient_frame(_state, _ctx), do: 0

  defp elapsed_state_frame(%{started_at_ms: started_at_ms}, now)
       when is_integer(started_at_ms) and is_integer(now) do
    elapsed_frame(started_at_ms, now)
  end

  defp elapsed_state_frame(_state, _now), do: 0

  defp attr(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end

  defp attr(attrs, key, default) when is_list(attrs) do
    Keyword.get(attrs, key, default)
  end

  defp attr(_attrs, _key, default), do: default

  defp rgb_color?({red, green, blue})
       when red in 0..255 and green in 0..255 and blue in 0..255,
       do: true

  defp rgb_color?(_color), do: false

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

  defp wave(phase) do
    (:math.sin(phase * 2 * :math.pi()) + 1) / 2
  end
end
