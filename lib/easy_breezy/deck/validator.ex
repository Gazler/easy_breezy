defmodule EasyBreezy.Deck.Validator do
  @moduledoc false

  @choices %{
    layout: [:title, :bullets, :image, :code, :breeze, :two_column, :markdown, :presenter],
    transition: [:slide, :slide_up]
  }
  @choice_aliases %{
    {:layout, "two-column"} => :two_column,
    {:layout, "two-cols"} => :two_column,
    {:layout, "split"} => :two_column,
    {:layout, "breeze-view"} => :breeze,
    {:layout, "breeze_view"} => :breeze,
    {:layout, "live"} => :breeze,
    {:layout, "view"} => :breeze,
    {:transition, "slide-up"} => :slide_up
  }
  @frontmatter_keys ~w(
    after_markdown alt assigns breeze_class breeze_focus breeze_focusable breeze_style class
    code_focus_ranges code_language code_path disable_transitions focus focusable footer height
    hide_transition hide_transitions id image_path items language layout left_items left_mode
    left_path left_title live_id module notes path prefix reveal right_mode right_notice right_path
    right_title source speaker start_opts steps style subtitle sync_live_state theme title transition
    view width
  )a
  @frontmatter_keys_by_name Map.new(@frontmatter_keys, fn key -> {Atom.to_string(key), key} end)
  @atom_keys [:id, :layout, :transition, :theme, :left_mode, :right_mode, :reveal]

  def validate!(%{source: source, entries: entries} = parsed)
      when is_binary(source) and is_list(entries) do
    entries =
      entries
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, index} -> validate_entry(entry, index, source) end)

    %{parsed | entries: entries}
  end

  defp validate_entry(entry, index, source) do
    context = %{source: source, entry: entry, index: index}

    metadata =
      entry.frontmatter
      |> coerce_frontmatter!(context)
      |> validate_metadata(context)

    entry
    |> Map.delete(:frontmatter)
    |> Map.put(:meta, metadata)
  end

  defp validate_metadata(metadata, %{index: 1, entry: %{body: ""}})
       when not is_map_key(metadata, :layout),
       do: metadata

  defp validate_metadata(metadata, context), do: validate_slide!(metadata, context)

  defp validate_slide!(metadata, context) do
    metadata
    |> Map.put_new(:layout, :markdown)
    |> Map.put_new(:transition, :slide)
    |> normalize_choice!(:layout, context)
    |> normalize_choice!(:transition, context)
  end

  defp normalize_choice!(metadata, key, context) do
    value = Map.fetch!(metadata, key)
    normalized = canonical_choice(key, value)
    allowed = Map.fetch!(@choices, key)

    if normalized in allowed do
      Map.put(metadata, key, normalized)
    else
      error!(context, "unsupported #{key} #{inspect(value)}; expected one of #{inspect(allowed)}")
    end
  end

  defp canonical_choice(key, value) when is_atom(value) do
    canonical_choice(key, Atom.to_string(value))
  end

  defp canonical_choice(key, value) when is_binary(value) do
    value = String.trim(value)

    Map.get(@choice_aliases, {key, value}) ||
      Enum.find(Map.fetch!(@choices, key), fn choice ->
        Atom.to_string(choice) == String.replace(value, "-", "_")
      end)
  end

  defp canonical_choice(_key, _value), do: nil

  defp coerce_frontmatter!(frontmatter, context) do
    ensure_unique_keys!(frontmatter, context)
    Map.new(frontmatter, &coerce_entry(&1, context))
  end

  defp ensure_unique_keys!(frontmatter, context) do
    duplicate =
      frontmatter
      |> Enum.map(&normalize_key(&1.key))
      |> Enum.frequencies()
      |> Enum.find(&duplicate_key?/1)

    case duplicate do
      {key, _count} -> error!(context, "duplicate frontmatter key `#{key}`")
      nil -> :ok
    end
  end

  defp duplicate_key?({_key, count}), do: count > 1

  defp coerce_entry(%{key: raw_key, value: value}, context) do
    key = frontmatter_key!(raw_key, context)
    {key, coerce_value(key, value)}
  end

  defp frontmatter_key!(raw_key, context) do
    key = normalize_key(raw_key)

    case Map.fetch(@frontmatter_keys_by_name, key) do
      {:ok, atom_key} -> atom_key
      :error -> error!(context, "unsupported frontmatter key `#{raw_key}`")
    end
  end

  defp normalize_key(key), do: String.replace(key, "-", "_")

  defp coerce_value(key, raw_value) do
    value = String.trim(raw_value)

    cond do
      value == "" ->
        ""

      value in ["true", "false"] ->
        value == "true"

      value in ["nil", "null"] ->
        nil

      String.match?(value, ~r/^-?\d+$/) ->
        String.to_integer(value)

      String.match?(value, ~r/^(['"]).*\1$/) ->
        unquote_string(value)

      String.starts_with?(value, "[") and String.ends_with?(value, "]") ->
        parse_list(value)

      String.match?(value, ~r/^\d+\.\.\d+$/) ->
        parse_range(value)

      String.starts_with?(value, ":") ->
        value |> String.trim_leading(":") |> String.to_atom()

      key in @atom_keys and String.match?(value, ~r/^[a-z_][a-zA-Z0-9_]*$/) ->
        String.to_atom(value)

      true ->
        value
    end
  end

  defp unquote_string(value) do
    value
    |> String.slice(1..-2//1)
    |> String.replace(~S(\"), ~S("))
  end

  defp parse_list(value) do
    value
    |> String.slice(1..-2//1)
    |> String.split(",", trim: true)
    |> Enum.map(fn item -> coerce_value(nil, item) end)
  end

  defp parse_range(value) do
    [first, last] = String.split(value, "..", parts: 2)
    {String.to_integer(first), String.to_integer(last)}
  end

  defp error!(context, message) do
    line = source_line(context.source, Map.get(context.entry, :source_range))

    raise ArgumentError,
          "invalid deck entry #{context.index} on line #{line}: #{message}"
  end

  defp source_line(source, {offset, _length}) when is_integer(offset) and offset >= 0 do
    source
    |> binary_part(0, min(offset, byte_size(source)))
    |> :binary.matches("\n")
    |> length()
    |> Kernel.+(1)
  end

  defp source_line(_source, _range), do: 1
end
