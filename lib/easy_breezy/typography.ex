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

  attr(:class, :string, default: nil)
  attr(:style, :any, default: nil)
  attr(:theme_colors, :map, default: %{})
  attr(:background, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def h1(assigns) do
    theme_colors = Map.get(assigns, :theme_colors, %{})
    background = Map.get(assigns, :background)

    source =
      assigns
      |> render_slot_text()
      |> String.trim_trailing("\n")
      |> String.upcase()
      |> bannerize()

    {gradient, class} = parse_gradient_class(assigns[:class])

    assigns =
      assigns
      |> assign(class: merge_class("bold", class))
      |> assign(content: maybe_apply_gradient(source, gradient, theme_colors, background))

    ~H"""
    <box class={@class} style={Breeze.Blocks.inline_style(assigns)} {@rest}>{@content}</box>
    """
  end

  defp bannerize(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> Enum.reduce(List.duplicate("", 6), fn grapheme, rows ->
      glyph =
        grapheme
        |> then(&Map.get(banner_font(), &1, fallback_glyph(&1)))
        |> normalize_glyph()

      Enum.zip_with(rows, glyph, fn row, segment ->
        row <>
          if row == "" do
            segment
          else
            " " <> segment
          end
      end)
    end)
    |> Enum.join("\n")
  end

  defp normalize_glyph(rows) when is_list(rows) do
    width =
      rows
      |> Enum.map(&String.length/1)
      |> Enum.max(fn -> 0 end)

    Enum.map(rows, &String.pad_trailing(&1, width))
  end

  defp banner_font do
    %{
      " " => List.duplicate("   ", 6),
      "A" => [
        " █████╗ ",
        "██╔══██╗",
        "███████║",
        "██╔══██║",
        "██║  ██║",
        "╚═╝  ╚═╝"
      ],
      "B" => [
        "██████╗",
        "██╔══██╗",
        "██████╔╝",
        "██╔══██╗",
        "██████╔╝",
        "╚═════╝"
      ],
      "E" => [
        "███████╗",
        "██╔════╝",
        "█████╗  ",
        "██╔══╝  ",
        "███████╗",
        "╚══════╝"
      ],
      "R" => [
        "██████╗ ",
        "██╔══██╗",
        "██████╔╝",
        "██╔══██╗",
        "██║  ██║",
        "╚═╝  ╚═╝"
      ],
      "S" => [
        "███████╗",
        "██╔════╝",
        "███████╗",
        "╚════██║",
        "███████║",
        "╚══════╝"
      ],
      "Y" => [
        "██╗   ██╗",
        "╚██╗ ██╔╝",
        " ╚████╔╝ ",
        "  ╚██╔╝  ",
        "   ██║   ",
        "   ╚═╝   "
      ],
      "Z" => [
        "███████╗",
        "╚══███╔╝",
        "  ███╔╝ ",
        " ███╔╝  ",
        "███████╗",
        "╚══════╝"
      ]
    }
  end

  defp fallback_glyph(grapheme) do
    padded = String.pad_trailing(grapheme, 3)
    List.duplicate(padded, 6)
  end

  defp render_slot_text(assigns) do
    assigns.inner_block
    |> render_slot()
    |> IO.iodata_to_binary()
  end

  defp parse_gradient_class(nil), do: {nil, nil}
  defp parse_gradient_class(""), do: {nil, nil}

  defp parse_gradient_class(class) when is_binary(class) do
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

    box_class =
      tokens
      |> Enum.reject(fn token ->
        token == direction or String.starts_with?(token, "from-") or
          String.starts_with?(token, "to-")
      end)
      |> Enum.join(" ")
      |> case do
        "" -> nil
        other -> other
      end

    gradient =
      case {direction, from, to} do
        {nil, _, _} -> nil
        {_, nil, _} -> nil
        {_, _, nil} -> nil
        _ -> %{direction: direction, from: from, to: to}
      end

    {gradient, box_class}
  end

  defp maybe_apply_gradient(text, nil, _theme_colors, _background), do: text

  defp maybe_apply_gradient(text, gradient, theme_colors, background) do
    with {:ok, from} <- resolve_gradient_color(gradient.from, theme_colors),
         {:ok, to} <- resolve_gradient_color(gradient.to, theme_colors),
         true <- rgb_color?(from),
         true <- rgb_color?(to) do
      apply_gradient(text, gradient.direction, from, to, background)
    else
      _ -> text
    end
  end

  defp resolve_gradient_color(name, theme_colors) when is_binary(name) do
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

  defp apply_gradient(text, "text-gradient-to-b", from, to, background) do
    text
    |> String.split("\n", trim: false)
    |> apply_line_gradient(from, to, background)
  end

  defp apply_gradient(text, "text-gradient-to-t", from, to, background) do
    text
    |> String.split("\n", trim: false)
    |> apply_line_gradient(to, from, background)
  end

  defp apply_gradient(text, "text-gradient-to-l", from, to, background),
    do: apply_character_gradient(text, to, from, background)

  defp apply_gradient(text, _direction, from, to, background),
    do: apply_character_gradient(text, from, to, background)

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
