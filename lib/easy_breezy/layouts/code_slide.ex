defmodule EasyBreezy.Layouts.CodeSlide do
  @moduledoc false

  use Breeze.View

  import Breeze.Blocks

  alias BackBreeze.VirtualText
  alias Breeze.Theme

  attr(:title, :string, required: true)
  attr(:language, :string, default: "text")
  attr(:source, :string, required: true)
  attr(:path, :string, default: nil)
  attr(:focus_ranges, :list, default: [])
  attr(:body_width, :integer, required: true)
  attr(:body_height, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def lumis_theme_name(:system16), do: "github_dark_dimmed"
  def lumis_theme_name(:system), do: "github_dark_dimmed"
  def lumis_theme_name(:nebula), do: "cyberdream_dark"
  def lumis_theme_name(:catppuccin), do: "catppuccin_macchiato"
  def lumis_theme_name(:dracula), do: "dracula"
  def lumis_theme_name(:gruvbox), do: "gruvbox_material_dark"
  def lumis_theme_name(:nord), do: "nordfox"
  def lumis_theme_name(:solarized_light), do: "solarized_spring_light"
  def lumis_theme_name(_theme_name), do: "github_dark_dimmed"

  def step_count(focus_ranges) do
    if step_indexed_focus_ranges?(focus_ranges) do
      max(length(focus_ranges) - 1, 0)
    else
      nil
    end
  end

  def focus_ranges_for_step(focus_ranges, step) do
    if step_indexed_focus_ranges?(focus_ranges) do
      Enum.at(focus_ranges, max(step, 0), List.last(focus_ranges) || [])
    else
      focus_ranges || []
    end
  end

  def code_slide(assigns) do
    fade = Map.get(assigns.render_context, :fade, 0)
    code_theme = Map.get(assigns.render_context, :code_theme, "github_dark")
    theme_colors = Map.get(assigns.render_context, :theme_colors, %{})
    transition? = Map.get(assigns.render_context, :transition?, false)
    viewport_height = code_viewport_height(assigns.body_height, assigns.path)

    snapshot_key =
      render_snapshot_key(
        assigns.source,
        assigns.language,
        code_theme,
        theme_colors,
        assigns.focus_ranges,
        assigns.body_width,
        viewport_height
      )

    snapshot =
      assigns.render_context
      |> Map.get(:code_slide_snapshots, %{})
      |> Map.get_lazy(snapshot_key, fn ->
        render_snapshot(
          assigns.source,
          assigns.language,
          code_theme,
          theme_colors,
          assigns.focus_ranges,
          assigns.body_width,
          viewport_height
        )
      end)

    rendered_lines =
      if transition? do
        []
      else
        Enum.map(snapshot.lines, fn line ->
          Map.put(
            line,
            :style,
            code_line_style(theme_colors, fade, snapshot.focus_active?, line.focused?)
          )
        end)
      end

    chrome_fade = if(snapshot.focus_active?, do: max(fade, 55), else: fade)

    assigns =
      assigns
      |> assign(fade: fade)
      |> assign(theme_colors: theme_colors)
      |> assign(transition?: transition?)
      |> assign(transition_content: snapshot.virtual_content)
      |> assign(
        transition_content_class:
          code_content_class("height-full overflow-hidden bg-panel", snapshot.target_scroll_y)
      )
      |> assign(rendered_lines: rendered_lines)
      |> assign(scrolled?: snapshot.target_scroll_y > 0)
      |> assign(gutter_left: snapshot.gutter_left)
      |> assign(target_scroll_y: snapshot.target_scroll_y)
      |> assign(chrome_fade: chrome_fade)
      |> assign(primary_style: fade_role_style(theme_colors, :primary, chrome_fade))
      |> assign(muted_style: fade_role_style(theme_colors, :muted, chrome_fade))
      |> assign(border_style: fade_role_style(theme_colors, :stroke, chrome_fade))
      |> assign(
        panel_style:
          fade_panel_style(theme_colors, fade, %{
            border_color: fade_border_color(theme_colors, chrome_fade)
          })
      )
      |> assign(
        scroll_panel_style:
          fade_panel_style(theme_colors, fade, %{
            border_color: fade_border_color(theme_colors, chrome_fade),
            scrollbar: code_scrollbar_style(theme_colors, chrome_fade)
          })
      )

    ~H"""
    <box class="width-full height-full">
      <box class="bold text-primary" style={@primary_style}>{@title}</box>
      <box :if={@path} class="text-muted" style={@muted_style}>{@path}</box>
      <box class="height-full border-rounded border border-stroke bg-panel" style={@panel_style}>
        <box class="absolute top-0" style={Map.merge(@border_style, %{left: @gutter_left})}>┬</box>
        <box class="absolute" style={Map.merge(@border_style, %{left: @gutter_left, bottom: -2})}>
          ┴
        </box>
        <.scroll
          :if={!@transition? && !@scrolled?}
          id="slide-code-top"
          class="height-full overflow-scroll bg-panel"
          style={@scroll_panel_style}
        >
          <box :for={line <- @rendered_lines} id={line.id} class="width-full" style={line.style}>
            {line.content}
          </box>
        </.scroll>
        <box
          :if={!@transition? && @scrolled?}
          id={"slide-code-focus-#{@target_scroll_y}"}
          focusable
          implicit={EasyBreezy.Layouts.CodeSlide.FocusScroll}
          scroll-target-y={@target_scroll_y}
          class="height-full overflow-scroll bg-panel"
          style={@scroll_panel_style}
        >
          <box :for={line <- @rendered_lines} id={line.id} class="width-full" style={line.style}>
            {line.content}
          </box>
        </box>
        <box :if={@transition?} class={@transition_content_class} style={@panel_style}>
          {@transition_content}
        </box>
      </box>
    </box>
    """
  end

  def render_snapshot_key(
        source,
        language,
        code_theme,
        theme_colors,
        focus_ranges,
        body_width,
        body_height
      ) do
    {__MODULE__, :render_snapshot, source, language, code_theme, theme_colors, focus_ranges,
     body_width, body_height}
  end

  def render_snapshot(
        source,
        language,
        code_theme,
        theme_colors,
        focus_ranges,
        body_width,
        viewport_height
      ) do
    source_lines = split_code_lines(source)
    total_lines = length(source_lines)
    line_number_width = total_lines |> max(1) |> Integer.digits() |> length()
    highlighted_lines = highlight_code_lines(source, language, code_theme, theme_colors)
    focus_ranges = normalize_focus_ranges(focus_ranges)
    focus_active? = focus_ranges != []

    lines =
      source_lines
      |> Enum.with_index(1)
      |> Enum.map(fn {raw_line, line_number} ->
        highlighted_line = Enum.at(highlighted_lines, line_number - 1, raw_line)
        focused? = line_in_ranges?(line_number, focus_ranges)

        %{
          id: "slide-code-#{line_number}",
          focused?: focused?,
          content:
            format_code_line(
              line_number,
              line_number_width,
              body_width,
              maybe_dim_code_line_content(
                highlighted_line,
                theme_colors,
                focus_active?,
                focused?
              ),
              theme_colors,
              focus_active?,
              focused?
            )
        }
      end)

    content = Enum.map_join(lines, "\n", & &1.content)

    %{
      lines: lines,
      content: content,
      virtual_content:
        virtual_snapshot_content(
          lines,
          render_snapshot_key(
            source,
            language,
            code_theme,
            theme_colors,
            focus_ranges,
            body_width,
            viewport_height
          )
        ),
      focus_active?: focus_active?,
      gutter_left: line_number_width + 2,
      target_scroll_y: code_target_scroll_y(focus_ranges, total_lines, viewport_height)
    }
  end

  def code_viewport_height(body_height, path) do
    title_height = 1
    path_height = if path in [nil, ""], do: 0, else: 1
    panel_border_height = 2

    body_height
    |> Kernel.-(title_height + path_height + panel_border_height)
    |> max(1)
  end

  defp code_content_class(base, scroll_y) when is_integer(scroll_y) and scroll_y > 0 do
    "#{base} offset-top-#{scroll_y}"
  end

  defp code_content_class(base, _scroll_y), do: base

  defp split_code_lines(source) do
    lines = String.split(source, "\n", trim: false)

    case lines do
      [] -> []
      _ -> if(List.last(lines) == "", do: Enum.drop(lines, -1), else: lines)
    end
  end

  defp virtual_snapshot_content(lines, cache_key) do
    content_lines = Enum.map(lines, & &1.content)
    line_count = length(content_lines)
    intrinsic_width = Enum.reduce(content_lines, 0, &max(visible_width(&1), &2))
    tuple_lines = List.to_tuple(content_lines)

    VirtualText.lazy(
      cache_key: {:code_slide_snapshot, :erlang.phash2(cache_key)},
      intrinsic_width: intrinsic_width,
      line_count_fn: fn _width -> line_count end,
      slice_fn: fn start_line, count, _width ->
        last_line = min(start_line + count - 1, line_count - 1)

        if count <= 0 or start_line > last_line do
          []
        else
          Enum.map(start_line..last_line, &elem(tuple_lines, &1))
        end
      end
    )
  end

  defp highlight_code_lines(source, language, code_theme, theme_colors) do
    if Code.ensure_loaded?(Lumis) and function_exported?(Lumis, :highlight!, 2) do
      default_bg =
        case Map.get(theme_colors, :panel) do
          {r, g, b} -> rgb_to_hex(r, g, b)
          _ -> nil
        end

      source
      |> Lumis.highlight!(
        formatter: {:terminal, language: language, theme: code_theme, background: default_bg}
      )
      |> split_code_lines()
      |> normalize_code_line_resets(theme_colors)
    else
      split_code_lines(source)
    end
  rescue
    _ -> split_code_lines(source)
  end

  defp normalize_code_line_resets(lines, theme_colors) when is_list(lines) do
    restore = ansi_panel_restore(theme_colors)

    if restore == "" do
      lines
    else
      Enum.map(lines, &replace_nonterminal_resets(&1, restore))
    end
  end

  defp replace_nonterminal_resets(content, restore) do
    case Regex.run(~r/^(.*?)(\e\[0m)?$/s, content, capture: :all_but_first) do
      [body, final_reset] ->
        String.replace(body, "\e[0m", restore) <> (final_reset || "")

      _ ->
        content
    end
  end

  defp code_line_style(theme_colors, amount, focus_active?, focused?)

  defp code_line_style(theme_colors, amount, false, _focused?) do
    case {Map.get(theme_colors, :panel), Map.get(theme_colors, :text)} do
      {{_, _, _} = panel, {_, _, _} = text} ->
        fade_style(amount, %{background_color: panel, foreground_color: text})

      {{_, _, _} = panel, _} ->
        fade_style(amount, %{background_color: panel})

      _ ->
        fade_style(amount, %{})
    end
  end

  defp code_line_style(theme_colors, amount, true, true),
    do: code_line_style(theme_colors, amount, false, true)

  defp code_line_style(theme_colors, amount, true, false) do
    dim_amount = max(amount, 55)

    case {Map.get(theme_colors, :panel), Map.get(theme_colors, :text)} do
      {{_, _, _} = panel, {_, _, _} = text} ->
        fade_style(dim_amount, %{
          background_color: panel,
          foreground_color: Theme.blend(text, panel, dim_amount / 100)
        })

      _ ->
        code_line_style(theme_colors, dim_amount, false, true)
    end
  end

  defp maybe_dim_code_line_content(content, _theme_colors, false, _focused?), do: content
  defp maybe_dim_code_line_content(content, _theme_colors, true, true), do: content

  defp maybe_dim_code_line_content(content, theme_colors, true, false) do
    dim_ansi_content(content, theme_colors, 0.55)
  end

  defp dim_ansi_content(content, %{panel: {_, _, _} = panel}, amount) when is_binary(content) do
    Regex.replace(~r/\e\[([0-9;]+)m/, content, fn _, params ->
      params =
        params
        |> String.split(";", trim: true)
        |> dim_ansi_params(panel, amount, [])
        |> Enum.join(";")

      "\e[" <> params <> "m"
    end)
  end

  defp dim_ansi_content(content, _theme_colors, _amount), do: content

  defp dim_ansi_params(["38", "2", red, green, blue | rest], background, amount, acc) do
    {dim_red, dim_green, dim_blue} =
      Theme.blend(
        {String.to_integer(red), String.to_integer(green), String.to_integer(blue)},
        background,
        amount
      )

    dim_ansi_params(
      rest,
      background,
      amount,
      acc ++
        [
          "38",
          "2",
          Integer.to_string(dim_red),
          Integer.to_string(dim_green),
          Integer.to_string(dim_blue)
        ]
    )
  end

  defp dim_ansi_params([param | rest], background, amount, acc) do
    dim_ansi_params(rest, background, amount, acc ++ [param])
  end

  defp dim_ansi_params([], _background, _amount, acc), do: acc

  defp fade_style(0, style), do: style

  defp fade_style(amount, style) do
    Map.merge(style, %{mute: amount})
  end

  defp fade_role_style(theme_colors, role, amount) do
    case {Map.get(theme_colors, role), Map.get(theme_colors, :bg)} do
      {{_, _, _} = color, {_, _, _} = bg} ->
        %{foreground_color: Theme.blend(color, bg, amount / 100)}

      _ ->
        fade_style(amount, %{})
    end
  end

  defp fade_panel_style(theme_colors, amount, extra) do
    case {Map.get(theme_colors, :panel), Map.get(theme_colors, :stroke),
          Map.get(theme_colors, :bg)} do
      {{_, _, _} = panel, {_, _, _} = stroke, {_, _, _} = bg} ->
        Map.merge(
          %{
            background_color: Theme.blend(panel, bg, amount / 100),
            border_color: Theme.blend(stroke, bg, amount / 100),
            foreground_color: Theme.blend(Map.get(theme_colors, :text) || bg, bg, amount / 100)
          },
          extra
        )

      _ ->
        fade_style(amount, extra)
    end
  end

  defp fade_border_color(theme_colors, amount) do
    case {Map.get(theme_colors, :stroke), Map.get(theme_colors, :bg)} do
      {{_, _, _} = stroke, {_, _, _} = bg} -> Theme.blend(stroke, bg, amount / 100)
      _ -> nil
    end
  end

  defp code_scrollbar_style(theme_colors, amount) do
    panel = Map.get(theme_colors, :panel)
    stroke = fade_border_color(theme_colors, amount) || Map.get(theme_colors, :stroke)

    %{
      arrows: %{
        foreground_color: stroke,
        background_color: panel
      },
      thumb: %{
        foreground_color: stroke,
        background_color: panel
      },
      track: %{
        foreground_color: stroke,
        background_color: panel
      },
      intersection: %{
        foreground_color: stroke,
        background_color: panel
      }
    }
  end

  defp rgb_to_hex(r, g, b) do
    "#" <>
      String.pad_leading(Integer.to_string(r, 16), 2, "0") <>
      String.pad_leading(Integer.to_string(g, 16), 2, "0") <>
      String.pad_leading(Integer.to_string(b, 16), 2, "0")
  end

  defp normalize_focus_ranges(ranges) when is_list(ranges) do
    ranges
    |> Enum.flat_map(fn
      first..last//_step when is_integer(first) and is_integer(last) ->
        [ordered_range(first, last)]

      {first, last} when is_integer(first) and is_integer(last) ->
        [ordered_range(first, last)]

      line when is_integer(line) ->
        [{line, line}]

      _ ->
        []
    end)
    |> Enum.reject(fn {first, last} -> first < 1 or last < 1 end)
    |> Enum.sort_by(fn {first, last} -> {first, last} end)
    |> merge_focus_ranges()
  end

  defp normalize_focus_ranges(_ranges), do: []

  defp ordered_range(first, last) when first <= last, do: {first, last}
  defp ordered_range(first, last), do: {last, first}

  defp merge_focus_ranges(ranges) do
    ranges
    |> Enum.reduce([], fn
      {first, last}, [{previous_first, previous_last} | rest]
      when first <= previous_last + 1 ->
        [{previous_first, max(previous_last, last)} | rest]

      range, acc ->
        [range | acc]
    end)
    |> Enum.reverse()
  end

  defp step_indexed_focus_ranges?(ranges) when is_list(ranges) do
    ranges != [] and Enum.all?(ranges, &is_list/1)
  end

  defp step_indexed_focus_ranges?(_ranges), do: false

  defp line_in_ranges?(_line_number, []), do: false

  defp line_in_ranges?(line_number, ranges) do
    Enum.any?(ranges, fn {first, last} -> line_number >= first and line_number <= last end)
  end

  defp format_code_line(
         line_number,
         width,
         body_width,
         content,
         theme_colors,
         focus_active?,
         focused?
       ) do
    gutter = code_gutter(line_number, width, theme_colors, focus_active?, focused?)
    line = gutter <> content
    line <> line_end_restore(line, body_width, theme_colors)
  end

  defp code_gutter(line_number, width, theme_colors, focus_active?, focused?) do
    number =
      line_number
      |> Integer.to_string()
      |> String.pad_leading(width)

    color =
      gutter_color(theme_colors, focus_active?, focused?) ||
        Map.get(theme_colors, :text) ||
        Map.get(theme_colors, :muted)

    ansi_gutter_style(color, theme_colors) <> number <> " │ " <> ansi_panel_restore(theme_colors)
  end

  defp gutter_color(theme_colors, false, _focused?), do: Map.get(theme_colors, :muted)
  defp gutter_color(theme_colors, true, true), do: Map.get(theme_colors, :muted)

  defp gutter_color(theme_colors, true, false) do
    case {Map.get(theme_colors, :muted), Map.get(theme_colors, :panel)} do
      {{_, _, _} = muted, {_, _, _} = panel} -> Theme.blend(muted, panel, 0.55)
      _ -> Map.get(theme_colors, :muted)
    end
  end

  defp ansi_gutter_style({red, green, blue}, %{panel: {pr, pg, pb}}),
    do: "\e[48;2;#{pr};#{pg};#{pb};38;2;#{red};#{green};#{blue}m"

  defp ansi_gutter_style({red, green, blue}, _theme_colors),
    do: "\e[38;2;#{red};#{green};#{blue}m"

  defp ansi_gutter_style(_color, theme_colors), do: ansi_panel_restore(theme_colors)

  defp ansi_panel_restore(%{panel: {pr, pg, pb}, text: {tr, tg, tb}}) do
    "\e[48;2;#{pr};#{pg};#{pb};38;2;#{tr};#{tg};#{tb}m"
  end

  defp ansi_panel_restore(%{panel: {pr, pg, pb}}) do
    "\e[48;2;#{pr};#{pg};#{pb}m"
  end

  defp ansi_panel_restore(_theme_colors), do: ""

  defp line_end_restore(line, body_width, theme_colors) do
    if visible_width(line) > body_width do
      IO.ANSI.reset() <> ansi_panel_restore(theme_colors)
    else
      ansi_panel_restore(theme_colors)
    end
  end

  defp visible_width(content) do
    content
    |> String.replace(~r/\e\[[0-9;]*m/, "")
    |> String.length()
  end

  defp code_target_scroll_y([], _total_lines, _viewport_height), do: 0

  defp code_target_scroll_y(ranges, total_lines, viewport_height) do
    {first, last} = hd(ranges)
    viewport_height = max(viewport_height, 1)
    max_scroll = max(total_lines - viewport_height, 0)
    focus_height = last - first + 1

    if focus_height > viewport_height do
      first - 1
    else
      div(first + last, 2) - 1 - div(viewport_height, 2)
    end
    |> max(0)
    |> min(max_scroll)
  end
end

defmodule EasyBreezy.Layouts.CodeSlide.FocusScroll do
  @moduledoc false

  alias Breeze.Viewport

  def init(_children, root_attrs, _last_state) do
    {:ok, %{offset_y: scroll_target(root_attrs)}, requires_layout_rerender: true}
  end

  def handle_event(_, _, state), do: {:noreply, state}

  def handle_modifiers(:root, flags, state) do
    [scroll_y: effective_offset_y(state, Keyword.get(flags, :layout_element))]
  end

  def handle_modifiers(:child, _flags, _state), do: []

  defp effective_offset_y(state, nil), do: Map.get(state, :offset_y, 0)

  defp effective_offset_y(state, %Viewport{} = viewport) do
    state
    |> Map.get(:offset_y, 0)
    |> Viewport.clamp_scroll_y(viewport)
  end

  defp scroll_target(attrs) do
    case Map.get(attrs, :"scroll-target-y", 0) do
      value when is_integer(value) and value > 0 -> value
      _other -> 0
    end
  end
end
