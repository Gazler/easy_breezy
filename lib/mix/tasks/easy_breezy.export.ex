defmodule Mix.Tasks.EasyBreezy.Export do
  use Mix.Task

  @shortdoc "Export an Easy Breezy Markdown deck to a single HTML file"

  @moduledoc """
  Exports an Easy Breezy Markdown deck using a fixed terminal viewport and an
  explicitly selected Breeze theme.

      mix easy_breezy.export slides.md --theme nebula

  Live view modules referenced by Markdown can be loaded before parsing. The
  require option accepts individual files or wildcards:

      mix easy_breezy.export slides.md \
        --theme nebula \
        --require 'examples/slides/*.ex' \
        --output slides.html

  ## Options

    * `--theme` - required built-in Breeze theme
    * `--output`, `-o` - output path; defaults beside the Markdown deck
    * `--columns` - terminal columns; defaults to 100
    * `--rows` - terminal rows; defaults to 30
    * `--steps` - `all`, `first`, or `last`; defaults to `all`
    * `--require` - Elixir source file or wildcard to load first; may be repeated
  """

  @switches [
    theme: :string,
    output: :string,
    columns: :integer,
    rows: :integer,
    steps: :string,
    require: :keep
  ]
  @aliases [o: :output]
  @theme_names Breeze.Theme.default_cycle() |> Enum.map(&Atom.to_string/1)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, inputs, invalid} = parse_argv(args)

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    {deck_path, require_patterns} = extract_inputs!(inputs)

    theme = opts |> Keyword.get(:theme) |> parse_theme!()
    steps = opts |> Keyword.get(:steps, "all") |> parse_steps!()

    require_patterns
    |> Enum.flat_map(&expand_require!/1)
    |> Enum.uniq()
    |> Enum.each(fn path -> Code.require_file(Path.expand(path)) end)

    export_opts = [
      theme: theme,
      size: {Keyword.get(opts, :columns, 100), Keyword.get(opts, :rows, 30)},
      steps: steps,
      output: Keyword.get(opts, :output, Path.rootname(deck_path) <> ".html")
    ]

    case EasyBreezy.Export.html(deck_path, export_opts) do
      {:ok, output} -> Mix.shell().info("Exported #{output}")
      {:error, reason} -> Mix.raise("export failed: #{inspect(reason)}")
    end
  end

  defp parse_theme!(nil), do: Mix.raise("--theme is required (for example: --theme nebula)")

  defp parse_theme!(theme) when theme in @theme_names, do: String.to_existing_atom(theme)

  defp parse_theme!(theme) do
    Mix.raise("unknown theme #{inspect(theme)}; choose one of: #{Enum.join(@theme_names, ", ")}")
  end

  defp parse_steps!("all"), do: :all
  defp parse_steps!("first"), do: :first
  defp parse_steps!("last"), do: :last

  defp parse_steps!(value),
    do: Mix.raise("--steps must be all, first, or last; got #{inspect(value)}")

  # OptionParser separates parsed options from positional arguments, which
  # loses the ordering of repeated --require groups expanded by the shell.
  # Retain option and positional inputs in argv order while parsing instead.
  defp parse_argv(args), do: parse_argv(args, [], [], [])

  defp parse_argv([], opts, inputs, invalid) do
    {Enum.reverse(opts), Enum.reverse(inputs), Enum.reverse(invalid)}
  end

  defp parse_argv(["--" | rest], opts, inputs, invalid) do
    inputs = Enum.reduce(rest, inputs, &[{:positional, &1} | &2])
    {Enum.reverse(opts), Enum.reverse(inputs), Enum.reverse(invalid)}
  end

  defp parse_argv(args, opts, inputs, invalid) do
    parser_opts = [strict: @switches, aliases: @aliases]

    case OptionParser.next(args, parser_opts) do
      {:ok, :require, value, rest} ->
        parse_argv(rest, opts, [{:require, value} | inputs], invalid)

      {:ok, key, value, rest} ->
        parse_argv(rest, [{key, value} | opts], inputs, invalid)

      {:invalid, option, value, rest} ->
        parse_argv(rest, opts, inputs, [{option, value} | invalid])

      {:undefined, option, _value, rest} ->
        parse_argv(rest, opts, inputs, [{option, nil} | invalid])

      {:error, [value | rest]} ->
        parse_argv(rest, opts, [{:positional, value} | inputs], invalid)
    end
  end

  # An unquoted shell wildcard leaves its first match attached to --require
  # and its remaining matches as positional arguments. Markdown is the one
  # deck input; every other positional path is another require match.
  defp extract_inputs!(inputs) do
    deck_paths =
      for {:positional, path} <- inputs,
          EasyBreezy.Deck.Markdown.markdown_path?(path),
          do: path

    require_patterns =
      Enum.flat_map(inputs, fn
        {:require, pattern} ->
          [pattern]

        {:positional, path} ->
          if EasyBreezy.Deck.Markdown.markdown_path?(path), do: [], else: [path]
      end)

    case deck_paths do
      [deck_path] -> {Path.expand(deck_path), require_patterns}
      [] -> Mix.raise("expected one Markdown deck path")
      _paths -> Mix.raise("expected one Markdown deck path, got #{length(deck_paths)}")
    end
  end

  defp expand_require!(pattern) do
    matches =
      pattern
      |> Path.expand()
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    case matches do
      [] -> Mix.raise("--require did not match any files: #{pattern}")
      paths -> paths
    end
  end
end
