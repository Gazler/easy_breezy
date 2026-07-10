defmodule EasyBreezy.Deck.Markdown do
  @moduledoc false

  alias EasyBreezy.{Deck, Slide}
  alias EasyBreezy.Deck.Markdown.FrontmatterParser
  alias EasyBreezy.Deck.Markdown.LineParser

  def load!(path) when is_binary(path) do
    path
    |> File.read!()
    |> parse!(base_path: Path.dirname(Path.expand(path)))
  end

  def parse!(source, opts \\ []) when is_binary(source) do
    source
    |> normalize_newlines()
    |> split_entries()
    |> build_deck(opts)
  end

  def markdown_path?(path) when is_binary(path) do
    Path.extname(path) in [".md", ".markdown"]
  end

  def markdown_path?(_path), do: false

  def content_blocks(source) when is_binary(source) do
    source
    |> String.split(["\r\n", "\n"], trim: false)
    |> collect_content_blocks([], [], nil, 0)
    |> Enum.reverse()
  end

  defp normalize_newlines(source), do: String.replace(source, "\r\n", "\n")

  defp split_entries(source) do
    {starts_with_delimiter?, chunks} = split_delimited_chunks(source)

    case {starts_with_delimiter?, chunks} do
      {false, [single]} ->
        [%{meta: %{}, body: single}]

      {true, chunks} ->
        pair_frontmatter_entries(chunks)

      {false, chunks} ->
        entries_after_leading_body(chunks)
    end
  end

  defp split_delimited_chunks(source) do
    chunks =
      source
      |> String.split("\n", trim: false)
      |> Enum.reduce([[]], fn line, [current | chunks] ->
        if LineParser.delimiter?(line) do
          [[] | [current | chunks]]
        else
          [[line | current] | chunks]
        end
      end)
      |> Enum.reverse()
      |> Enum.map(&lines_to_chunk/1)

    case chunks do
      ["" | rest] -> {true, rest}
      chunks -> {false, chunks}
    end
  end

  defp lines_to_chunk(lines) do
    lines
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp pair_frontmatter_entries(parts) do
    parts
    |> Enum.chunk_every(2, 2, [""])
    |> Enum.map(fn [frontmatter, body] -> frontmatter_entry(frontmatter, body) end)
    |> reject_empty_entries()
  end

  defp entries_after_leading_body([body | parts]) do
    [%{meta: %{}, body: String.trim(body, "\n")} | entries_after_body(parts)]
    |> reject_empty_entries()
  end

  defp entries_after_body([]), do: []
  defp entries_after_body([body]), do: [%{meta: %{}, body: String.trim(body, "\n")}]

  defp entries_after_body([frontmatter, body | rest]) do
    if frontmatter_block?(frontmatter) do
      [frontmatter_entry(frontmatter, body) | entries_after_body(rest)]
    else
      [%{meta: %{}, body: String.trim(frontmatter, "\n")} | entries_after_body([body | rest])]
    end
  end

  defp frontmatter_entry(frontmatter, body) do
    %{meta: parse_frontmatter!(frontmatter), body: String.trim(body, "\n")}
  end

  defp reject_empty_entries(entries) do
    Enum.reject(entries, fn entry -> entry.meta == %{} and String.trim(entry.body) == "" end)
  end

  defp frontmatter_block?(frontmatter) do
    case FrontmatterParser.frontmatter(frontmatter) do
      {:ok, entries, "", _context, _line, _offset} -> entries != []
      _ -> false
    end
  end

  defp parse_frontmatter!(frontmatter) do
    case FrontmatterParser.frontmatter(frontmatter) do
      {:ok, entries, "", _context, _line, _offset} ->
        Map.new(entries, fn {:entry, [key, value]} ->
          key = key |> normalize_key() |> String.to_atom()
          {key, parse_value(key, value)}
        end)

      {:error, reason, rest, _context, {line, _column}, _offset} ->
        raise ArgumentError,
              "invalid slide frontmatter on line #{line}: #{reason} near #{inspect(rest)}"
    end
  end

  defp normalize_key(key), do: String.replace(key, "-", "_")

  defp parse_value(key, value) do
    value = String.trim(value)

    cond do
      value == "" -> ""
      value in ["true", "false"] -> value == "true"
      value in ["nil", "null"] -> nil
      integer?(value) -> String.to_integer(value)
      quoted?(value) -> unquote_string(value)
      list?(value) -> parse_list(value)
      range?(value) -> parse_range(value)
      String.starts_with?(value, ":") -> value |> String.trim_leading(":") |> String.to_atom()
      atom_key?(key) and atom?(value) -> String.to_atom(value)
      true -> value
    end
  end

  defp parse_value(value), do: parse_value(nil, value)

  defp integer?(value), do: String.match?(value, ~r/^-?\d+$/)
  defp quoted?(value), do: String.match?(value, ~r/^(['"]).*\1$/)
  defp list?(value), do: String.starts_with?(value, "[") and String.ends_with?(value, "]")
  defp range?(value), do: String.match?(value, ~r/^\d+\.\.\d+$/)
  defp atom?(value), do: String.match?(value, ~r/^[a-z_][a-zA-Z0-9_]*$/)

  defp atom_key?(key) do
    key in [
      :id,
      :layout,
      :transition,
      :theme,
      :left_mode,
      :right_mode,
      :reveal
    ]
  end

  defp unquote_string(value), do: value |> String.slice(1..-2//1) |> unescape_string()
  defp unescape_string(value), do: String.replace(value, ~S(\"), ~S("))

  defp parse_list(value) do
    value
    |> String.slice(1..-2//1)
    |> split_list_items()
    |> Enum.map(&parse_value/1)
  end

  defp split_list_items(""), do: []

  defp split_list_items(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp parse_range(value) do
    [first, last] = String.split(value, "..", parts: 2)
    {String.to_integer(first), String.to_integer(last)}
  end

  defp build_deck(entries, opts) do
    {deck_meta, slide_entries} = split_deck_meta(entries)
    base_path = Keyword.get(opts, :base_path, File.cwd!())

    slides =
      slide_entries
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, index} -> build_slide(entry, index, base_path) end)

    %Deck{
      title: Map.get(deck_meta, :title) || first_slide_title(slides) || "Untitled Deck",
      slides: slides
    }
  end

  defp split_deck_meta([%{meta: meta, body: body} | rest])
       when not is_map_key(meta, :layout) and body == "" do
    {meta, rest}
  end

  defp split_deck_meta(entries), do: {%{}, entries}

  defp first_slide_title([%Slide{title: title} | _]), do: title
  defp first_slide_title(_slides), do: nil

  defp build_slide(%{meta: meta, body: body}, index, base_path) do
    layout = meta |> Map.get(:layout, :markdown) |> normalize_layout()
    title = Map.get(meta, :title) || infer_title(body) || "Slide #{index}"
    payload_meta = Map.put(meta, :title, title)
    payload = payload_for(layout, payload_meta, body, base_path)

    %Slide{
      id: Map.get(payload_meta, :id) || slide_id(title, index),
      title: title,
      layout: layout,
      payload: payload,
      steps: Map.get(payload_meta, :steps, default_steps(layout, payload_meta, body)),
      transition: Map.get(payload_meta, :transition, :slide),
      disable_transitions?: disable_transitions?(payload_meta, payload)
    }
  end

  defp disable_transitions?(meta, payload) do
    Enum.reduce_while(
      [:disable_transitions?, :disable_transitions, :hide_transition, :hide_transitions],
      image_payload?(payload),
      fn key, default ->
        case Map.fetch(meta, key) do
          {:ok, value} -> {:halt, value}
          :error -> {:cont, default}
        end
      end
    )
  end

  defp normalize_layout(value) when is_binary(value) do
    case value do
      "two-column" -> :two_column
      "two_column" -> :two_column
      "two-cols" -> :two_column
      "split" -> :two_column
      "breeze" -> :breeze
      "breeze-view" -> :breeze
      "breeze_view" -> :breeze
      "live" -> :breeze
      "view" -> :breeze
      layout -> String.to_atom(layout)
    end
  end

  defp normalize_layout(value), do: value

  defp image_payload?(%{left_mode: mode}) when mode in [:image, "image"], do: true
  defp image_payload?(%{right_mode: mode}) when mode in [:image, "image"], do: true
  defp image_payload?(_payload), do: false

  defp slide_id(title, index) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> then(fn
      "" -> :"slide_#{index}"
      id -> String.to_atom(id)
    end)
  end

  defp infer_title(body) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn
      "# " <> title -> String.trim(title)
      _line -> nil
    end)
  end

  defp payload_for(:title, meta, body, _base_path) do
    meta
    |> Map.take([:title, :prefix, :subtitle, :speaker, :footer, :notes])
    |> Map.put_new(:notes, notes_from_body(body))
  end

  defp payload_for(:bullets, meta, body, _base_path) do
    after_markdown = Map.get(meta, :after_markdown) || after_bullets_markdown(body)

    meta
    |> Map.take([:title, :notes])
    |> Map.put(:items, Map.get(meta, :items) || bullet_items(body))
    |> maybe_put(:reveal, Map.get(meta, :reveal))
    |> maybe_put(:after_markdown, after_markdown)
    |> Map.put_new(:notes, notes_from_body(body))
  end

  defp payload_for(:code, meta, body, base_path) do
    path = Map.get(meta, :path) || Map.get(meta, :code_path)
    source = Map.get(meta, :source) || code_source(path, strip_notes(body), base_path)
    focus_steps = List.wrap(Map.get(meta, :focus))

    payload = %{
      title: Map.get(meta, :title),
      code_language: Map.get(meta, :language) || Map.get(meta, :code_language) || "text",
      code_source: source,
      code_path: path,
      code_focus_ranges: Map.get(meta, :code_focus_ranges) || [],
      notes: Map.get(meta, :notes) || notes_from_body(body)
    }

    if focus_steps == [] do
      payload
    else
      fn _body_width, step ->
        %{payload | code_focus_ranges: code_focus_ranges_for_step(focus_steps, step)}
      end
    end
  end

  defp payload_for(:breeze, meta, _body, _base_path) do
    %{
      title: Map.get(meta, :title),
      view: breeze_view!(Map.get(meta, :view) || Map.get(meta, :module)),
      live_id: Map.get(meta, :live_id),
      start_opts: Map.get(meta, :start_opts, []),
      assigns: Map.get(meta, :assigns, %{}),
      breeze_class:
        Map.get(meta, :breeze_class) || Map.get(meta, :class) || "width-full height-full",
      breeze_style: Map.get(meta, :breeze_style) || Map.get(meta, :style),
      breeze_focusable: Map.get(meta, :breeze_focusable, Map.get(meta, :focusable, true)),
      sync_live_state: Map.get(meta, :sync_live_state, true)
    }
  end

  defp payload_for(:two_column, meta, body, base_path) do
    slots = body |> strip_notes() |> split_slots()
    left = Map.get(slots, :left) || Map.get(slots, :default, "")
    right = Map.get(slots, :right, "")

    {left_title, left_body} = slot_title(left)
    {right_title, right_body} = slot_title(right)

    left_image = markdown_image_path(left_body, base_path)
    right_image = markdown_image_path(right_body, base_path)
    left_text = remove_markdown_images(left_body)
    right_text = remove_markdown_images(right_body)
    left_items = bullet_items(left_text)

    left_mode = Map.get(meta, :left_mode) || if(left_image, do: :image, else: :text)
    right_mode = Map.get(meta, :right_mode) || if(right_image, do: :image, else: :text)
    left_path = Map.get(meta, :left_path) || left_image
    right_path = Map.get(meta, :right_path) || right_image

    %{
      title: Map.get(meta, :title),
      left_title: Map.get(meta, :left_title) || left_title,
      left_items: left_items,
      left_lines: left_lines(left_text, left_items),
      reveal: Map.get(meta, :reveal),
      left_mode: left_mode,
      left_path: resolve_image_path(left_path, left_mode, base_path),
      right_title: Map.get(meta, :right_title) || right_title,
      right_lines: code_or_text_lines(right_text),
      right_notice: Map.get(meta, :right_notice),
      right_mode: right_mode,
      right_path: resolve_image_path(right_path, right_mode, base_path)
    }
  end

  defp payload_for(:markdown, meta, body, _base_path) do
    markdown = strip_notes(body, preserve_step_markers?: true)

    %{
      title: Map.get(meta, :title),
      markdown: markdown,
      markdown_blocks: content_blocks(markdown),
      notes: Map.get(meta, :notes) || notes_from_body(body)
    }
  end

  defp payload_for(_layout, meta, body, _base_path) do
    meta
    |> Map.put_new(:title, Map.get(meta, :title) || infer_title(body))
    |> Map.put_new(:markdown, strip_notes(body))
    |> Map.put_new(:notes, notes_from_body(body))
  end

  defp code_focus_ranges_for_step(_focus_steps, step) when step <= 0, do: []

  defp code_focus_ranges_for_step(focus_steps, step) do
    focus_steps
    |> Enum.at(step - 1)
    |> List.wrap()
  end

  defp code_source(nil, body, _base_path), do: strip_code_fence(body)

  defp code_source(path, _body, base_path) when is_binary(path) do
    base_path
    |> Path.join(path)
    |> Path.expand()
    |> File.read!()
  end

  defp strip_code_fence(body) do
    lines = body |> String.trim() |> String.split("\n", trim: false)

    case lines do
      [first | rest] ->
        code_lines = Enum.drop(rest, -1)
        last = List.last(rest)

        if last && LineParser.code_fence_open?(first) && LineParser.fence_close?(last) do
          Enum.join(code_lines, "\n")
        else
          body
        end

      _ ->
        body
    end
  end

  defp breeze_view!(nil) do
    raise ArgumentError, "breeze slides require a `view:` frontmatter value"
  end

  defp breeze_view!(module) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir." <> _ -> module
      module -> module_from_string(module)
    end
  end

  defp breeze_view!(module) when is_binary(module) do
    module
    |> String.trim()
    |> String.trim_leading(":")
    |> module_from_string()
  end

  defp module_from_string("Elixir." <> module), do: module_from_string(module)

  defp module_from_string(module) do
    module
    |> String.split(".", trim: true)
    |> Module.concat()
  end

  defp split_slots(body) do
    body
    |> String.split("\n", trim: false)
    |> Enum.reduce({:default, %{default: []}}, fn line, {slot, slots} ->
      case LineParser.slot(line) do
        nil ->
          {slot, Map.update(slots, slot, [line], &[line | &1])}

        name ->
          slot = name |> normalize_key() |> String.to_atom()
          {slot, Map.put_new(slots, slot, [])}
      end
    end)
    |> elem(1)
    |> Map.new(fn {slot, lines} ->
      {slot, lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()}
    end)
  end

  defp slot_title(body) do
    lines = String.split(body, "\n", trim: false)

    case lines do
      ["# " <> title | rest] -> {String.trim(title), rest |> Enum.join("\n") |> String.trim()}
      _ -> {nil, body}
    end
  end

  defp markdown_image_path(body, base_path) do
    body
    |> String.split("\n", trim: false)
    |> Enum.find_value(&LineParser.markdown_image_path/1)
    |> then(fn
      nil -> nil
      path -> resolve_asset_path(path, base_path)
    end)
  end

  defp remove_markdown_images(body) do
    body
    |> String.split("\n", trim: false)
    |> Enum.map(&LineParser.remove_markdown_images/1)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp resolve_asset_path(path, base_path) do
    cond do
      URI.parse(path).scheme != nil -> path
      Path.type(path) == :absolute -> path
      true -> Path.expand(path, base_path)
    end
  end

  defp resolve_image_path(nil, _mode, _base_path), do: nil

  defp resolve_image_path(path, mode, base_path) when mode in [:image, "image"],
    do: resolve_asset_path(path, base_path)

  defp resolve_image_path(path, _mode, _base_path), do: path

  defp left_lines(_body, [_ | _]), do: []

  defp left_lines(body, _items) do
    body
    |> markdown_text_lines()
    |> Enum.map(&{"", &1})
  end

  defp code_or_text_lines(body) do
    body
    |> strip_code_fence()
    |> markdown_text_lines()
  end

  defp collect_content_blocks([], markdown_lines, blocks, nil, step) do
    append_markdown_block(markdown_lines, blocks, step)
  end

  defp collect_content_blocks([], _markdown_lines, blocks, {:mermaid, mermaid_lines}, step) do
    append_mermaid_block(mermaid_lines, blocks, step)
  end

  defp collect_content_blocks([], _markdown_lines, blocks, {:breeze, breeze_lines}, step) do
    append_breeze_block(breeze_lines, blocks, step)
  end

  defp collect_content_blocks([line | rest], markdown_lines, blocks, nil, step) do
    cond do
      step_marker_line?(line) ->
        collect_content_blocks(
          rest,
          [],
          append_markdown_block(markdown_lines, blocks, step),
          nil,
          step + 1
        )

      mermaid_fence_open?(line) ->
        collect_content_blocks(
          rest,
          [],
          append_markdown_block(markdown_lines, blocks, step),
          {:mermaid, []},
          step
        )

      breeze_fence_open?(line) ->
        collect_content_blocks(
          rest,
          [],
          append_markdown_block(markdown_lines, blocks, step),
          {:breeze, []},
          step
        )

      true ->
        collect_content_blocks(rest, [line | markdown_lines], blocks, nil, step)
    end
  end

  defp collect_content_blocks(
         [line | rest],
         _markdown_lines,
         blocks,
         {:mermaid, mermaid_lines},
         step
       ) do
    if fence_close?(line) do
      collect_content_blocks(
        rest,
        [],
        append_mermaid_block(mermaid_lines, blocks, step),
        nil,
        step
      )
    else
      collect_content_blocks(rest, [], blocks, {:mermaid, [line | mermaid_lines]}, step)
    end
  end

  defp collect_content_blocks(
         [line | rest],
         _markdown_lines,
         blocks,
         {:breeze, breeze_lines},
         step
       ) do
    if fence_close?(line) do
      collect_content_blocks(rest, [], append_breeze_block(breeze_lines, blocks, step), nil, step)
    else
      collect_content_blocks(rest, [], blocks, {:breeze, [line | breeze_lines]}, step)
    end
  end

  defp append_markdown_block(lines, blocks, step) do
    lines
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
    |> then(fn
      "" -> blocks
      content -> [%{type: :markdown, content: content, step: step} | blocks]
    end)
  end

  defp append_mermaid_block(lines, blocks, step) do
    content =
      lines
      |> Enum.reverse()
      |> Enum.join("\n")
      |> String.trim()

    [%{type: :mermaid, content: content, step: step} | blocks]
  end

  defp append_breeze_block(lines, blocks, step) do
    content =
      lines
      |> Enum.reverse()
      |> Enum.join("\n")
      |> String.trim()

    [%{type: :breeze, content: content, step: step} | blocks]
  end

  defp step_marker_line?(line), do: line |> String.trim() |> step_marker_comment?()

  defp step_marker_count(source) do
    source
    |> String.split(["\r\n", "\n"], trim: false)
    |> Enum.count(&step_marker_line?/1)
  end

  defp mermaid_fence_open?(line), do: LineParser.mermaid_fence_open?(line)
  defp breeze_fence_open?(line), do: LineParser.breeze_fence_open?(line)
  defp fence_close?(line), do: LineParser.fence_close?(line)

  defp markdown_text_lines(body) do
    body
    |> String.split("\n", trim: false)
    |> Enum.map(&String.trim_trailing/1)
  end

  defp default_steps(:bullets, meta, body) do
    items = Map.get(meta, :items, bullet_items(body))
    after_markdown = Map.get(meta, :after_markdown) || after_bullets_markdown(body)
    after_markdown_steps = step_marker_count(after_markdown || "")

    cond do
      immediate_reveal?(Map.get(meta, :reveal)) -> after_markdown_steps
      markdown_present?(after_markdown) and items != [] -> length(items) + after_markdown_steps
      true -> max(length(items) - 1, 0)
    end
  end

  defp default_steps(:code, meta, _body) do
    meta
    |> Map.get(:focus, [])
    |> List.wrap()
    |> length()
  end

  defp default_steps(:two_column, meta, body) do
    slots = body |> strip_notes() |> split_slots()
    left = Map.get(slots, :left) || Map.get(slots, :default, "")
    {_left_title, left_body} = slot_title(left)
    item_count = length(Map.get(meta, :left_items) || bullet_items(left_body))

    cond do
      immediate_reveal?(Map.get(meta, :reveal)) -> 0
      Map.get(meta, :right_notice) && item_count > 0 -> item_count
      true -> max(item_count - 1, 0)
    end
  end

  defp default_steps(:markdown, _meta, body) do
    body
    |> strip_notes(preserve_step_markers?: true)
    |> step_marker_count()
  end

  defp default_steps(_layout, _meta, _body), do: 0

  defp immediate_reveal?(value), do: value in [:immediate, "immediate"]

  defp bullet_items(body) do
    body
    |> strip_notes()
    |> String.split("\n")
    |> nested_bullet_items()
  end

  defp nested_bullet_items(lines) do
    {items, current, _base_indent} =
      Enum.reduce(lines, {[], nil, nil}, fn line, {items, current, base_indent} ->
        case LineParser.bullet_with_indent(line) do
          nil ->
            {items, current, base_indent}

          %{indent: indent, item: item} ->
            append_bullet_item(items, current, base_indent, indent, item)
        end
      end)

    items
    |> append_current_bullet(current)
    |> Enum.reverse()
  end

  defp append_bullet_item(items, nil, _base_indent, indent, item), do: {items, item, indent}

  defp append_bullet_item(items, current, base_indent, indent, item)
       when indent <= base_indent do
    {append_current_bullet(items, current), item, indent}
  end

  defp append_bullet_item(items, current, base_indent, indent, item) do
    nested_indent = String.duplicate(" ", indent - base_indent)
    {items, current <> "\n" <> nested_indent <> "- " <> item, base_indent}
  end

  defp append_current_bullet(items, nil), do: items
  defp append_current_bullet(items, current), do: [current | items]

  defp after_bullets_markdown(body) do
    body
    |> strip_notes(preserve_step_markers?: true)
    |> remove_leading_title()
    |> String.split("\n", trim: false)
    |> lines_after_last_bullet()
    |> Enum.join("\n")
    |> String.trim()
    |> blank_to_nil()
  end

  defp remove_leading_title(body) do
    case String.split(body, "\n", trim: false) do
      ["# " <> _title | rest] -> rest |> Enum.join("\n") |> String.trim_leading("\n")
      _lines -> body
    end
  end

  defp lines_after_last_bullet(lines) do
    last_bullet_index =
      lines
      |> Enum.with_index()
      |> Enum.reduce(nil, fn {line, index}, last_index ->
        if LineParser.bullet(line), do: index, else: last_index
      end)

    case last_bullet_index do
      nil -> []
      index -> Enum.drop(lines, index + 1)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp markdown_present?(value) when is_binary(value), do: String.trim(value) != ""
  defp markdown_present?(_value), do: false

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp notes_from_body(body) do
    body
    |> then(&Regex.scan(~r/<!--(.*?)-->/s, &1, capture: :all_but_first))
    |> Enum.map(fn [note] -> String.trim(note) end)
    |> Enum.reject(&step_marker_comment?/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      [note] -> note
      notes -> notes
    end
  end

  defp strip_notes(body, opts \\ []) do
    preserve_step_markers? = Keyword.get(opts, :preserve_step_markers?, false)

    Regex.replace(~r/<!--.*?-->/s, body, fn comment ->
      if preserve_step_markers? and step_marker_comment?(comment) do
        comment
      else
        ""
      end
    end)
    |> String.trim()
  end

  defp step_marker_comment?(comment) when is_binary(comment) do
    String.match?(String.trim(comment), ~r/^<!--\s*step\s*-->$/i) or
      String.match?(String.trim(comment), ~r/^step$/i)
  end
end
