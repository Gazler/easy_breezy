defmodule EasyBreezy.Implicit.TitleGradient do
  @moduledoc false

  alias Breeze.Theme

  @tick_ms 90
  @phase_count 120

  def init(_children, root_attrs, last_state) do
    state =
      last_state
      |> Map.put(:direction, attr(root_attrs, :gradient_direction, "text-gradient-to-r"))
      |> Map.put(:theme_colors, attr(root_attrs, :gradient_theme_colors, %{}))
      |> Map.put(:background, attr(root_attrs, :gradient_background, nil))
      |> Map.put(:source, attr(root_attrs, :gradient_source, nil))

    {:ok, state, rerender_every: @tick_ms}
  end

  def handle_modifiers(_type, _flags, _state), do: []

  def animate(:root, box, _flags, state, %{frame: frame, layout: %Breeze.Viewport{} = layout}) do
    with {:ok, from, to} <- gradient_colors(state.theme_colors, frame) do
      content = if is_binary(state.source), do: state.source, else: box.content

      content =
        EasyBreezy.Typography.gradient(content, state.direction, from, to, state.background)

      {:ok, %{box | content: content}, overlays: line_overlays(content, layout)}
    else
      _ -> box
    end
  end

  def animate(:root, box, _flags, state, %{frame: frame}) do
    with {:ok, from, to} <- gradient_colors(state.theme_colors, frame) do
      content = if is_binary(state.source), do: state.source, else: box.content

      content =
        EasyBreezy.Typography.gradient(content, state.direction, from, to, state.background)

      %{box | content: content}
    else
      _ -> box
    end
  end

  def animate(:child, box, _flags, _state, _ctx), do: box

  defp gradient_colors(theme_colors, frame) when is_map(theme_colors) do
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

  defp gradient_colors(_theme_colors, _frame), do: :error

  defp attr(attrs, key, default) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end

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
        no_wrap: true
      }
    end)
  end

  defp wave(phase) do
    (:math.sin(phase * 2 * :math.pi()) + 1) / 2
  end
end
