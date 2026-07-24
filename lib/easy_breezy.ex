defmodule EasyBreezy do
  @moduledoc """
  Generic slideshow helpers built on top of Breeze.
  """

  @reload_source_extensions [".ex", ".exs"]
  @reload_watch_extensions @reload_source_extensions ++ [".md", ".markdown"]

  def run(opts) do
    start_opts = start_opts(opts)
    reload_opts = reload_opts(opts)
    presenter_mode = presenter_mode(opts)

    Breeze.Example.run(
      [
        view: view_for_presenter_mode(presenter_mode),
        start_opts: start_opts,
        inspector: true,
        mouse: true,
        reload: reload_opts,
        hide_cursor: Keyword.get(opts, :hide_cursor, true),
        global_keybindings: Keyword.get(opts, :global_keybindings, [])
      ],
      keep_alive: Keyword.get(opts, :keep_alive, :infinity)
    )
  end

  def refresh_server_opts(opts, context) do
    refreshed =
      opts
      |> start_opts()
      |> preserve_slideshow_state(context)

    [start_opts: refreshed]
  end

  def refresh_server_opts(opts), do: refresh_server_opts(opts, %{})

  defp start_opts(opts) do
    opts
    |> Keyword.take([
      :alt_screen,
      :theme,
      :presenter,
      :presenter_mode,
      :presenter_sync_name,
      :sync_name,
      :presenter_sync_node,
      :sync_node,
      :source_editor,
      :source_save_notice,
      :source_mode?,
      :theme_status?,
      :themes
    ])
    |> Keyword.put(:presenter_mode, presenter_mode(opts))
    |> maybe_put_env(:sync_node, "EASY_BREEZY_SYNC_NODE")
    |> Keyword.put(:deck, resolve_deck(Keyword.fetch!(opts, :deck)))
  end

  defp presenter_mode(opts) do
    case Keyword.get(opts, :presenter_mode) || env_presenter_mode() ||
           Keyword.get(opts, :presenter, :single) do
      :presenter -> :presenter
      :presentation -> :presentation
      _mode -> :single
    end
  end

  defp view_for_presenter_mode(:presenter), do: EasyBreezy.PresenterView
  defp view_for_presenter_mode(_mode), do: EasyBreezy.Slideshow

  defp env_presenter_mode do
    case System.get_env("EASY_BREEZY_PRESENTER_MODE") do
      "presenter" -> :presenter
      "presentation" -> :presentation
      "slides" -> :presentation
      _value -> nil
    end
  end

  defp maybe_put_env(opts, key, env_name) do
    case {Keyword.has_key?(opts, key), System.get_env(env_name)} do
      {false, value} when is_binary(value) and value != "" -> Keyword.put(opts, key, value)
      _ -> opts
    end
  end

  defp reload_opts(opts) do
    case Keyword.get(opts, :reload, true) do
      false ->
        false

      nil ->
        nil

      true ->
        [
          enabled?: true,
          force?: true,
          paths: reload_paths(opts),
          files_fun: &reload_files/1,
          compile_fun: &compile_reload_files/1,
          refresh_server_opts: {__MODULE__, :refresh_server_opts, [opts]}
        ]

      reload_opts when is_list(reload_opts) ->
        reload_opts
        |> Keyword.put_new(:force?, true)
        |> Keyword.put_new(:paths, reload_paths(opts))
        |> Keyword.put_new(:files_fun, &reload_files/1)
        |> Keyword.put_new(:compile_fun, &compile_reload_files/1)
        |> Keyword.put_new(:refresh_server_opts, {__MODULE__, :refresh_server_opts, [opts]})
    end
  end

  defp reload_paths(opts) do
    root = Path.expand("..", __DIR__)
    paths = [Path.join(root, "lib"), Path.join(root, "examples")]

    case Keyword.get(opts, :deck) do
      path when is_binary(path) ->
        if EasyBreezy.Deck.Markdown.markdown_path?(path) do
          [Path.dirname(Path.expand(path)) | paths]
        else
          paths
        end

      _deck ->
        paths
    end
    |> Enum.uniq()
  end

  defp reload_files(paths) do
    paths
    |> Enum.flat_map(fn path ->
      if File.dir?(path) do
        Path.wildcard(Path.join(path, "**/*.{ex,exs,md,markdown}"))
      else
        []
      end
    end)
    |> Enum.filter(&(Path.extname(&1) in @reload_watch_extensions))
    |> Enum.uniq()
  end

  defp compile_reload_files(files) do
    previous = Code.compiler_options()
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Breeze.ReloadContext.with_compile(fn ->
        files
        |> Enum.filter(&reload_source_file?/1)
        |> Enum.each(&Code.compile_file/1)
      end)

      :ok
    rescue
      error -> {:error, error}
    after
      Code.compiler_options(previous)
    end
  end

  defp reload_source_file?(path) do
    File.regular?(path) and Path.extname(path) in @reload_source_extensions
  end

  defp resolve_deck({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, args)
  end

  defp resolve_deck(path) when is_binary(path) do
    if EasyBreezy.Deck.Markdown.markdown_path?(path) do
      EasyBreezy.Deck.Markdown.load!(path)
    else
      path
    end
  end

  defp resolve_deck(deck) when is_function(deck, 0), do: deck.()
  defp resolve_deck(deck), do: deck

  defp preserve_slideshow_state(start_opts, %{metadata: %{assigns: assigns}})
       when is_map(assigns) do
    start_opts
    |> maybe_put_assign(assigns, :slide_index)
    |> maybe_put_assign(assigns, :step)
    |> maybe_put_assign(assigns, :started_at_ms)
    |> maybe_put_assign(assigns, :timer_paused?)
    |> maybe_put_assign(assigns, :paused_elapsed_ms)
    |> maybe_put_assign(assigns, :source_editor)
    |> maybe_put_assign(assigns, :source_save_notice)
    |> maybe_put_assign(assigns, :source_mode?)
    |> maybe_put_assign(assigns, :theme_status?)
    |> maybe_put_presenter(assigns)
    |> maybe_put_theme(assigns)
  end

  defp preserve_slideshow_state(start_opts, _context), do: start_opts

  defp maybe_put_assign(start_opts, assigns, key) do
    case Map.fetch(assigns, key) do
      {:ok, value} -> Keyword.put(start_opts, key, value)
      :error -> start_opts
    end
  end

  defp maybe_put_presenter(start_opts, assigns) do
    case Map.fetch(assigns, :presenter?) do
      {:ok, value} -> Keyword.put(start_opts, :presenter, value)
      :error -> start_opts
    end
  end

  defp maybe_put_theme(start_opts, assigns) do
    case Map.fetch(assigns, :theme_name) do
      {:ok, value} -> Keyword.put(start_opts, :theme, value)
      :error -> start_opts
    end
  end
end
