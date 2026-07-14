defmodule EasyBreezy.PresenterSync do
  @moduledoc false

  alias EasyBreezy.PresenterSync.{Scope, Session, SessionSupervisor}

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

  @doc false
  def runtime_started? do
    Scope.started?() and is_pid(Process.whereis(SessionSupervisor))
  end

  @doc false
  def start_presentation(name, producer \\ self()) when is_pid(producer) do
    with :ok <- ensure_runtime_started(),
         nil <- whereis(name) do
      SessionSupervisor.start_session(name, producer)
    else
      pid when is_pid(pid) -> {:error, {:already_started, pid}}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def ensure_presentation(name, producer \\ self()) when is_pid(producer) do
    with :ok <- ensure_runtime_started() do
      case whereis(name) do
        nil ->
          SessionSupervisor.start_session(name, producer)

        pid ->
          case session_producer(pid) do
            {:ok, ^producer} -> {:ok, pid}
            {:ok, _other_producer} -> {:error, {:already_started, pid}}
            :error -> start_presentation(name, producer)
          end
      end
    end
  end

  def whereis(name) do
    case presentation_members(name) do
      [] ->
        maybe_connect_default_presentation_node()
        List.first(presentation_members(name))

      members ->
        Enum.find(members, &(node(&1) != node())) || List.first(members)
    end
  end

  def subscribe(name_or_session, subscriber \\ self()) when is_pid(subscriber) do
    with {:ok, pid} <- resolve_session(name_or_session) do
      send(pid, {:easy_breezy_presenter_subscribe, subscriber})
      {:ok, pid}
    else
      :error -> :error
    end
  end

  def command(name_or_session, command) do
    with {:ok, pid} <- resolve_session(name_or_session) do
      send(pid, {:easy_breezy_presenter_command, self(), command})
      :ok
    else
      :error -> :error
    end
  end

  def request_state(name_or_session, subscriber \\ self()) when is_pid(subscriber) do
    with {:ok, pid} <- resolve_session(name_or_session) do
      send(pid, {:easy_breezy_presenter_state_request, subscriber})
      :ok
    else
      :error -> :error
    end
  end

  @doc false
  def publish(name_or_session, revision, payload)
      when is_integer(revision) and revision >= 0 do
    with {:ok, pid} <- resolve_session(name_or_session) do
      Session.publish(pid, revision, payload)
      :ok
    else
      :error -> :error
    end
  end

  def publish(_name_or_session, _revision, _payload), do: {:error, :invalid_revision}

  defp resolve_session(pid) when is_pid(pid), do: {:ok, pid}

  defp resolve_session(name) do
    case whereis(name) do
      nil -> :error
      pid -> {:ok, pid}
    end
  end

  defp presentation_members(name) do
    if Scope.started?() do
      case :pg.get_members(Scope.name(), group(name)) do
        members when is_list(members) -> members
        _ -> []
      end
    else
      []
    end
  catch
    :exit, _reason -> []
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

  defp ensure_runtime_started do
    if runtime_started?(), do: :ok, else: {:error, :not_started}
  end

  defp session_producer(session) do
    {:ok, Session.producer(session)}
  catch
    :exit, _reason -> :error
  end
end
