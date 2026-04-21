defmodule EasyBreezy do
  @moduledoc """
  Generic slideshow helpers built on top of Breeze.
  """

  def run(opts) do
    start_opts = start_opts(opts)
    reload_opts = reload_opts(opts)

    Breeze.Example.run(
      [
        view: EasyBreezy.Slideshow,
        start_opts: start_opts,
        reload: reload_opts,
        hide_cursor: Keyword.get(opts, :hide_cursor, true),
        global_keybindings:
          Keyword.get(opts, :global_keybindings, [{"q", fn _event, term -> {:stop, term} end}])
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
    |> Keyword.take([:alt_screen, :theme, :presenter, :themes])
    |> Keyword.put(:deck, resolve_deck(Keyword.fetch!(opts, :deck)))
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
          paths: reload_paths(),
          refresh_server_opts: {__MODULE__, :refresh_server_opts, [opts]}
        ]

      reload_opts when is_list(reload_opts) ->
        reload_opts
        |> Keyword.put_new(:force?, true)
        |> Keyword.put_new(:paths, reload_paths())
        |> Keyword.put_new(:refresh_server_opts, {__MODULE__, :refresh_server_opts, [opts]})
    end
  end

  defp reload_paths do
    root = Path.expand("..", __DIR__)
    [Path.join(root, "lib"), Path.join(root, "examples")]
  end

  defp resolve_deck({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, args)
  end

  defp resolve_deck(deck) when is_function(deck, 0), do: deck.()
  defp resolve_deck(deck), do: deck

  defp preserve_slideshow_state(start_opts, %{metadata: %{assigns: assigns}})
       when is_map(assigns) do
    start_opts
    |> maybe_put_assign(assigns, :slide_index)
    |> maybe_put_assign(assigns, :step)
    |> maybe_put_assign(assigns, :started_at_ms)
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
