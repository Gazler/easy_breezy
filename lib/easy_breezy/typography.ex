defmodule EasyBreezy.Typography do
  @moduledoc """
  Experimental typography components.

  This module prototypes a higher-level API for display text without adding new
  renderer primitives yet. Gradient styling is currently implemented by
  expanding text into ANSI-colored content, so it is best treated as an API
  experiment rather than a final renderer design.
  """

  use Breeze.View

  import Breeze.Blocks, only: [merge_class: 2]

  alias Breeze.Theme

  @gradient_directions ~w(text-gradient-to-r text-gradient-to-l text-gradient-to-b text-gradient-to-t)
  @shimmer_classes ~w(text-shimmer)

  attr(:class, :string, default: nil)
  attr(:style, :any, default: nil)
  attr(:theme_colors, :map, default: %{})
  attr(:background, :any, default: nil)
  attr(:gradient_from, :any, default: nil)
  attr(:gradient_to, :any, default: nil)
  attr(:shimmer_base, :any, default: nil)
  attr(:shimmer_highlight, :any, default: nil)
  attr(:animation_frozen_now, :any, default: nil)
  attr(:id, :string, default: nil)
  attr(:implicit, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def text(assigns) do
    theme_colors = Map.get(assigns, :theme_colors, %{})
    background = Map.get(assigns, :background)
    source = render_slot_text(assigns)

    {_gradient, shimmer, class} =
      parse_text_effect_class(
        assigns[:class],
        nil,
        nil,
        assigns[:shimmer_base],
        assigns[:shimmer_highlight]
      )

    assigns =
      assigns
      |> assign(class: class)
      |> assign(content: maybe_apply_shimmer(source, shimmer, theme_colors, background, 0.0))
      |> assign(implicit: maybe_shimmer_implicit(assigns[:implicit], shimmer))
      |> assign(shimmer_source: source)
      |> assign(shimmer_base: shimmer && shimmer.base)
      |> assign(shimmer_highlight: shimmer && shimmer.highlight)

    ~H"""
    <box
      class={@class}
      id={@id}
      implicit={@implicit}
      style={Breeze.Blocks.inline_style(assigns)}
      shimmer_theme_colors={@theme_colors}
      shimmer_background={@background}
      shimmer_source={@shimmer_source}
      shimmer_base={@shimmer_base}
      shimmer_highlight={@shimmer_highlight}
      animation_frozen_now={@animation_frozen_now}
      {@rest}
    >
      {@content}
    </box>
    """
  end

  attr(:class, :string, default: nil)
  attr(:style, :any, default: nil)
  attr(:theme_colors, :map, default: %{})
  attr(:background, :any, default: nil)
  attr(:gradient_from, :any, default: nil)
  attr(:gradient_to, :any, default: nil)
  attr(:animation_frozen_now, :any, default: nil)
  attr(:shimmer_base, :any, default: nil)
  attr(:shimmer_highlight, :any, default: nil)
  attr(:id, :string, default: nil)
  attr(:implicit, :any, default: nil)
  attr(:font, :any, default: nil)
  attr(:letter_spacing, :integer, default: 0)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def h1(assigns) do
    heading(assigns, :ansi_shadow)
  end

  attr(:class, :string, default: nil)
  attr(:style, :any, default: nil)
  attr(:theme_colors, :map, default: %{})
  attr(:background, :any, default: nil)
  attr(:gradient_from, :any, default: nil)
  attr(:gradient_to, :any, default: nil)
  attr(:animation_frozen_now, :any, default: nil)
  attr(:shimmer_base, :any, default: nil)
  attr(:shimmer_highlight, :any, default: nil)
  attr(:id, :string, default: nil)
  attr(:implicit, :any, default: nil)
  attr(:font, :any, default: nil)
  attr(:letter_spacing, :integer, default: 0)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def h2(assigns) do
    heading(assigns, :future)
  end

  attr(:class, :string, default: nil)
  attr(:style, :any, default: nil)
  attr(:theme_colors, :map, default: %{})
  attr(:background, :any, default: nil)
  attr(:gradient_from, :any, default: nil)
  attr(:gradient_to, :any, default: nil)
  attr(:animation_frozen_now, :any, default: nil)
  attr(:shimmer_base, :any, default: nil)
  attr(:shimmer_highlight, :any, default: nil)
  attr(:id, :string, default: nil)
  attr(:implicit, :any, default: nil)
  attr(:font, :any, default: nil)
  attr(:letter_spacing, :integer, default: 0)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def h3(assigns) do
    heading(assigns, :js_stick_letters)
  end

  defp heading(assigns, default_font) do
    theme_colors = Map.get(assigns, :theme_colors, %{})
    background = Map.get(assigns, :background)
    font = Map.get(assigns, :font) || default_font

    source =
      assigns
      |> render_slot_text()
      |> String.trim_trailing("\n")
      |> String.upcase()
      |> EasyBreezy.Figlet.render(font,
        trim_vertical: true,
        letter_spacing: Map.get(assigns, :letter_spacing, 0)
      )

    {gradient, shimmer, class} =
      parse_text_effect_class(
        assigns[:class],
        assigns[:gradient_from],
        assigns[:gradient_to],
        assigns[:shimmer_base],
        assigns[:shimmer_highlight]
      )

    gradient_direction =
      case gradient || gradient_direction_from_class(assigns[:class]) do
        %{direction: direction} -> direction
        direction when is_binary(direction) -> direction
        _ -> "text-gradient-to-r"
      end

    assigns =
      assigns
      |> assign(class: merge_class("bold", class))
      |> assign(
        content: maybe_apply_text_effect(source, gradient, shimmer, theme_colors, background)
      )
      |> assign(implicit: maybe_shimmer_implicit(assigns[:implicit], shimmer))
      |> assign(gradient_direction: gradient_direction)
      |> assign(gradient_source: source)
      |> assign(shimmer_source: source)
      |> assign(shimmer_base: shimmer && shimmer.base)
      |> assign(shimmer_highlight: shimmer && shimmer.highlight)

    ~H"""
    <box
      class={@class}
      id={@id}
      implicit={@implicit}
      style={Breeze.Blocks.inline_style(assigns)}
      gradient_direction={@gradient_direction}
      gradient_theme_colors={@theme_colors}
      gradient_background={@background}
      gradient_source={@gradient_source}
      animation_frozen_now={@animation_frozen_now}
      shimmer_theme_colors={@theme_colors}
      shimmer_background={@background}
      shimmer_source={@shimmer_source}
      shimmer_base={@shimmer_base}
      shimmer_highlight={@shimmer_highlight}
      {@rest}
    >
      {@content}
    </box>
    """
  end

  defp render_slot_text(assigns) do
    assigns.inner_block
    |> render_slot()
    |> IO.iodata_to_binary()
  end

  defp parse_text_effect_class(nil, gradient_from, gradient_to, shimmer_base, shimmer_highlight) do
    shimmer = build_explicit_shimmer(shimmer_base, shimmer_highlight)

    {unless(shimmer, do: build_explicit_gradient(nil, gradient_from, gradient_to)), shimmer, nil}
  end

  defp parse_text_effect_class("", gradient_from, gradient_to, shimmer_base, shimmer_highlight) do
    parse_text_effect_class(nil, gradient_from, gradient_to, shimmer_base, shimmer_highlight)
  end

  defp parse_text_effect_class(class, gradient_from, gradient_to, shimmer_base, shimmer_highlight)
       when is_binary(class) do
    tokens = String.split(class, ~r/\s+/, trim: true)

    direction =
      Enum.find_value(tokens, fn
        token when token in @gradient_directions -> token
        _ -> nil
      end)

    from =
      Enum.find_value(
        tokens,
        &(String.starts_with?(&1, "from-") && String.replace_prefix(&1, "from-", ""))
      )

    to =
      Enum.find_value(
        tokens,
        &(String.starts_with?(&1, "to-") && String.replace_prefix(&1, "to-", ""))
      )

    shimmer? = Enum.any?(tokens, &(&1 in @shimmer_classes))

    box_class =
      tokens
      |> Enum.reject(fn token ->
        token == direction or token in @shimmer_classes or String.starts_with?(token, "from-") or
          String.starts_with?(token, "to-")
      end)
      |> Enum.join(" ")
      |> case do
        "" -> nil
        other -> other
      end

    shimmer =
      build_explicit_shimmer(shimmer_base, shimmer_highlight) ||
        if shimmer? and not is_nil(from) and not is_nil(to) do
          %{base: from, highlight: to}
        end

    gradient =
      unless shimmer do
        build_explicit_gradient(direction, gradient_from, gradient_to) ||
          case {direction, from, to} do
            {nil, _, _} -> nil
            {_, nil, _} -> nil
            {_, _, nil} -> nil
            _ -> %{direction: direction, from: from, to: to}
          end
      end

    {gradient, shimmer, box_class}
  end

  defp gradient_direction_from_class(class) when is_binary(class) do
    class
    |> String.split(~r/\s+/, trim: true)
    |> Enum.find(&(&1 in @gradient_directions))
  end

  defp gradient_direction_from_class(_class), do: nil

  defp build_explicit_gradient(direction, {_, _, _} = gradient_from, {_, _, _} = gradient_to) do
    %{direction: direction || "text-gradient-to-r", from: gradient_from, to: gradient_to}
  end

  defp build_explicit_gradient(_direction, _gradient_from, _gradient_to), do: nil

  defp build_explicit_shimmer(base, highlight) when not is_nil(base) and not is_nil(highlight) do
    %{base: base, highlight: highlight}
  end

  defp build_explicit_shimmer(_base, _highlight), do: nil

  defp maybe_apply_text_effect(text, _gradient, shimmer, theme_colors, background)
       when not is_nil(shimmer) do
    maybe_apply_shimmer(text, shimmer, theme_colors, background, 0.0)
  end

  defp maybe_apply_text_effect(text, gradient, _shimmer, theme_colors, background) do
    maybe_apply_gradient(text, gradient, theme_colors, background)
  end

  defp maybe_apply_gradient(text, nil, _theme_colors, _background), do: text

  defp maybe_apply_gradient(text, gradient, theme_colors, background) do
    with {:ok, from} <- resolve_text_color(gradient.from, theme_colors),
         {:ok, to} <- resolve_text_color(gradient.to, theme_colors),
         true <- rgb_color?(from),
         true <- rgb_color?(to) do
      gradient(text, gradient.direction, from, to, background)
    else
      _ -> text
    end
  end

  defp maybe_apply_shimmer(text, nil, _theme_colors, _background, _phase), do: text

  defp maybe_apply_shimmer(text, shimmer, theme_colors, background, phase) do
    with {:ok, base} <- resolve_text_color(shimmer.base, theme_colors),
         {:ok, highlight} <- resolve_text_color(shimmer.highlight, theme_colors),
         true <- rgb_color?(base),
         true <- rgb_color?(highlight) do
      shimmer(text, base, highlight, background, phase)
    else
      _ -> text
    end
  end

  defp maybe_shimmer_implicit(nil, shimmer) when not is_nil(shimmer),
    do: EasyBreezy.Implicit.TextShimmer

  defp maybe_shimmer_implicit(implicit, _shimmer), do: implicit

  defp resolve_text_color(name, theme_colors) when is_binary(name) do
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

  defp resolve_text_color({_, _, _} = color, _theme_colors), do: {:ok, color}

  defp fetch_theme_color(theme_colors, key) do
    case Map.get(theme_colors, key) do
      {_, _, _} = color -> {:ok, color}
      _ -> {:error, :missing_theme_color}
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

  defp rgb_color?({red, green, blue})
       when red in 0..255 and green in 0..255 and blue in 0..255,
       do: true

  defp rgb_color?(_color), do: false

  def gradient(text, "text-gradient-to-b", from, to, background) do
    text
    |> String.split("\n", trim: false)
    |> apply_line_gradient(from, to, background)
  end

  def gradient(text, "text-gradient-to-t", from, to, background) do
    text
    |> String.split("\n", trim: false)
    |> apply_line_gradient(to, from, background)
  end

  def gradient(text, "text-gradient-to-l", from, to, background),
    do: apply_character_gradient(text, to, from, background)

  def gradient(text, _direction, from, to, background),
    do: apply_character_gradient(text, from, to, background)

  def shimmer(text, base, highlight, background, phase) do
    phase = min(1.0, max(0.0, phase))

    text
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &apply_line_shimmer(&1, base, highlight, background, phase))
  end

  defp apply_line_gradient(lines, from, to, background) do
    total = max(length(lines) - 1, 1)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      color = interpolate_color(from, to, index / total)
      ansi_foreground(color, background) <> line
    end)
    |> Enum.join("\n")
  end

  defp apply_character_gradient(text, from, to, background) do
    text
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", fn line ->
      graphemes = String.graphemes(line)
      total = max(length(graphemes) - 1, 1)

      graphemes
      |> Enum.with_index()
      |> Enum.map_join(fn {grapheme, index} ->
        color = interpolate_color(from, to, index / total)
        ansi_foreground(color, background) <> grapheme
      end)
    end)
  end

  defp apply_line_shimmer(line, base, highlight, background, phase) do
    graphemes = String.graphemes(line)
    total = max(length(graphemes) - 1, 1)
    band_width = 0.18
    center = phase * (1 + band_width)

    graphemes
    |> Enum.with_index()
    |> Enum.map_join(fn {grapheme, index} ->
      position = index / total
      distance = abs(position - center)
      amount = max(0.0, 1.0 - distance / band_width)
      color = interpolate_color(base, highlight, amount * amount)

      ansi_foreground(color, background) <> grapheme
    end)
  end

  defp interpolate_color(from, to, amount) do
    Theme.blend(from, to, amount)
  end

  defp ansi_foreground({red, green, blue}, {br, bg, bb}) do
    Termite.Style.background({br, bg, bb})
    |> Termite.Style.foreground({red, green, blue})
    |> Termite.Style.open_code()
  end

  defp ansi_foreground({red, green, blue}, _theme_colors) do
    Termite.Style.foreground({red, green, blue})
    |> Termite.Style.open_code()
  end
end
