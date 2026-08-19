defmodule EasyBreezy.MixTask.PresenterMode do
  @moduledoc false

  @epmd :erl_epmd
  @nodes %{
    slides: :"slides@127.0.0.1",
    presenter: :"presenter@127.0.0.1"
  }

  @doc false
  def run(mode, args) when mode in [:slides, :presenter] and is_list(args) do
    args = run_args!(mode, args)
    ensure_epmd!(mode)
    start_distribution!(mode)
    System.put_env("EASY_BREEZY_PRESENTER_MODE", Atom.to_string(mode))
    Mix.Tasks.Run.run(args)
  end

  @doc false
  def run_args!(mode, []) when mode in [:slides, :presenter] do
    Mix.raise("""
    easy_breezy.#{mode} expects a script or other mix run arguments.

    For example:

        mix easy_breezy.#{mode} slides.exs
    """)
  end

  def run_args!(mode, args) when mode in [:slides, :presenter] and is_list(args), do: args

  @doc false
  def node_name(mode) when mode in [:slides, :presenter], do: Map.fetch!(@nodes, mode)

  @doc false
  def ensure_epmd!(mode, epmd_module \\ @epmd) when mode in [:slides, :presenter] do
    case epmd_module.names() do
      {:ok, _names} ->
        :ok

      {:error, reason} ->
        Mix.raise(epmd_error_message(mode, reason))
    end
  end

  @doc false
  def start_distribution!(mode, node_module \\ Node) when mode in [:slides, :presenter] do
    name = node_name(mode)

    case node_module.start(name, name_domain: :longnames) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Mix.raise(
          "easy_breezy.#{mode} could not start distributed Erlang as #{name} " <>
            "using long names: #{inspect(reason)}"
        )
    end
  end

  @doc false
  def epmd_error_message(mode, reason) when mode in [:slides, :presenter] do
    """
    easy_breezy.#{mode} requires epmd, but epmd does not appear to be running.

    Start epmd, then run `mix easy_breezy.#{mode}` again:

        epmd -daemon

    EPMD check failed with: #{inspect(reason)}
    """
    |> String.trim()
  end
end
