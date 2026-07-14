defmodule EasyBreezy.PresenterSync.Session do
  @moduledoc false

  use GenServer, restart: :temporary

  alias EasyBreezy.PresenterSync.Scope

  @input_keys ["key", "ctrlKey", "altKey", "shiftKey", "metaKey"]
  @scroll_keys ["ArrowDown", "ArrowUp", "j", "k"]

  defstruct [
    :name,
    :producer,
    :producer_monitor_ref,
    latest: nil,
    subscribers: %{}
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def publish(session, revision, payload) when is_pid(session) do
    GenServer.cast(session, {:publish, self(), revision, payload})
  end

  def latest(session) when is_pid(session) do
    GenServer.call(session, :latest)
  end

  def subscriber_count(session) when is_pid(session) do
    GenServer.call(session, :subscriber_count)
  end

  def producer(session) when is_pid(session) do
    GenServer.call(session, :producer)
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    producer = Keyword.fetch!(opts, :producer)

    with true <- Process.alive?(producer),
         [] <- :pg.get_members(Scope.name(), EasyBreezy.PresenterSync.group(name)),
         :ok <- :pg.join(Scope.name(), EasyBreezy.PresenterSync.group(name), self()) do
      state = %__MODULE__{
        name: name,
        producer: producer,
        producer_monitor_ref: Process.monitor(producer)
      }

      notify_subscriber_count(state)
      {:ok, state}
    else
      false -> {:stop, :producer_not_alive}
      [existing | _rest] -> {:stop, {:already_registered, existing}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:latest, _from, state), do: {:reply, state.latest, state}

  def handle_call(:subscriber_count, _from, state) do
    {:reply, map_size(state.subscribers), state}
  end

  def handle_call(:producer, _from, state), do: {:reply, state.producer, state}

  @impl true
  def handle_cast({:publish, producer, revision, payload}, %{producer: producer} = state) do
    case state.latest do
      {current_revision, _current_payload} when revision <= current_revision ->
        {:noreply, state}

      _ ->
        latest = {revision, payload}

        if payload_changed?(state.latest, payload) do
          broadcast(state.subscribers, latest)
        end

        {:noreply, %{state | latest: latest}}
    end
  end

  def handle_cast({:publish, _producer, _revision, _payload}, state), do: {:noreply, state}

  @impl true
  def handle_info({:easy_breezy_presenter_subscribe, subscriber}, state)
      when is_pid(subscriber) do
    {state, subscribed?} = put_subscriber(state, subscriber)

    if subscribed?, do: notify_subscriber_count(state)
    deliver_latest(subscriber, state.latest)

    if state.latest == nil do
      send(
        state.producer,
        {:easy_breezy_presenter_state_request, self(), subscriber}
      )
    end

    {:noreply, state}
  end

  def handle_info({:easy_breezy_presenter_state_request, subscriber}, state)
      when is_pid(subscriber) do
    if Map.has_key?(state.subscribers, subscriber) do
      case state.latest do
        nil ->
          send(
            state.producer,
            {:easy_breezy_presenter_state_request, self(), subscriber}
          )

        latest ->
          deliver_latest(subscriber, latest)
      end
    end

    {:noreply, state}
  end

  def handle_info({:easy_breezy_presenter_command, subscriber, command}, state)
      when is_pid(subscriber) do
    with true <- Map.has_key?(state.subscribers, subscriber),
         {:ok, command} <- normalize_command(command) do
      send(
        state.producer,
        {:easy_breezy_presenter_command, self(), subscriber, command}
      )
    end

    {:noreply, state}
  end

  def handle_info(
        {:DOWN, ref, :process, producer, _reason},
        %{producer: producer, producer_monitor_ref: ref} = state
      ) do
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, subscriber, _reason}, state) do
    case state.subscribers do
      %{^subscriber => ^ref} ->
        state = %{state | subscribers: Map.delete(state.subscribers, subscriber)}
        notify_subscriber_count(state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp put_subscriber(state, subscriber) do
    if Map.has_key?(state.subscribers, subscriber) do
      {state, false}
    else
      monitor_ref = Process.monitor(subscriber)
      subscribers = Map.put(state.subscribers, subscriber, monitor_ref)
      {%{state | subscribers: subscribers}, true}
    end
  end

  defp notify_subscriber_count(state) do
    send(
      state.producer,
      {:easy_breezy_presenter_subscribers, self(), map_size(state.subscribers)}
    )
  end

  defp deliver_latest(_subscriber, nil), do: :ok

  defp deliver_latest(subscriber, {revision, payload}) do
    send(
      subscriber,
      {:easy_breezy_presentation_state, self(), revision, payload}
    )
  end

  defp broadcast(subscribers, latest) do
    Enum.each(subscribers, fn {subscriber, _monitor_ref} ->
      deliver_latest(subscriber, latest)
    end)
  end

  defp payload_changed?(nil, _payload), do: true

  defp payload_changed?({_revision, current}, payload)
       when is_map(current) and is_map(payload) do
    Map.delete(current, :elapsed_ms) != Map.delete(payload, :elapsed_ms)
  end

  defp payload_changed?({_revision, current}, payload), do: current != payload

  defp normalize_command(command)
       when command in [
              :next,
              :previous,
              :home,
              :end,
              :cycle_theme,
              :reset_timer,
              :toggle_source_mode,
              :edit_source
            ],
       do: {:ok, command}

  defp normalize_command({:scroll, %{"key" => key} = event}) when key in @scroll_keys do
    {:ok, {:scroll, Map.take(event, @input_keys)}}
  end

  defp normalize_command({:input, %{"key" => key} = event}) when is_binary(key) do
    {:ok, {:input, Map.take(event, @input_keys)}}
  end

  defp normalize_command(_command), do: :error
end
