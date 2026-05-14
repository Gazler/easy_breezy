defmodule EasyBreezy.PresenterSync do
  @moduledoc false

  @default_name {:easy_breezy, :presentation}

  def group(name \\ @default_name), do: {__MODULE__, :presentations, name}

  def name(opts) do
    Keyword.get(opts, :presenter_sync_name) ||
      Keyword.get(opts, :sync_name) ||
      @default_name
  end

  def connect(nil), do: :ignored

  def connect(node) when is_atom(node) do
    Node.connect(node)
  end

  def connect(node) when is_binary(node) do
    node
    |> String.to_atom()
    |> connect()
  end

  def register(name) do
    ensure_registry_started()
    :pg.join(group(name), self())
  end

  def whereis(name) do
    ensure_registry_started()

    case presentation_members(name) do
      [] ->
        maybe_connect_default_presentation_node()
        List.first(presentation_members(name))

      members ->
        Enum.find(members, &(node(&1) != node())) || List.first(members)
    end
  end

  def subscribe(name) do
    case whereis(name) do
      nil ->
        :error

      pid ->
        send(pid, {:easy_breezy_presenter_subscribe, self()})
        {:ok, pid}
    end
  end

  def command(name, command) do
    case whereis(name) do
      nil ->
        :error

      pid ->
        send(pid, {:easy_breezy_presenter_command, self(), command})
        :ok
    end
  end

  def publish(subscribers, payload) do
    Enum.each(subscribers, &send(&1, {:easy_breezy_presentation_state, payload}))
  end

  defp presentation_members(name) do
    case :pg.get_members(group(name)) do
      members when is_list(members) -> members
      _ -> []
    end
  end

  defp maybe_connect_default_presentation_node do
    case default_presentation_node(node()) do
      nil ->
        false

      target when target == node() ->
        false

      target ->
        Node.connect(target)
    end
  end

  defp default_presentation_node(current_node) when is_atom(current_node) do
    case Atom.to_string(current_node) do
      "nonode@nohost" ->
        nil

      name ->
        case String.split(name, "@", parts: 2) do
          ["slides", _host] -> nil
          [_node_name, host] when host != "" -> String.to_atom("slides@" <> host)
          _ -> nil
        end
    end
  end

  defp default_presentation_node(_current_node), do: nil

  defp ensure_registry_started do
    case Process.whereis(:pg) do
      nil ->
        case :pg.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end
end
