defmodule EasyBreezy.PresenterSyncTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.PresenterSync
  alias EasyBreezy.PresenterSync.{Scope, Session, SessionSupervisor}

  test "a session owns discovery and exits when its producer exits" do
    name = unique_name()
    producer = start_producer(self())

    assert {:ok, session} = PresenterSync.start_presentation(name, producer)
    assert PresenterSync.whereis(name) == session
    assert Session.producer(session) == producer

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 0}}

    assert {:ok, ^session} = PresenterSync.ensure_presentation(name, producer)

    other_producer = start_producer(self())

    assert {:error, {:already_started, ^session}} =
             PresenterSync.ensure_presentation(name, other_producer)

    session_ref = Process.monitor(session)
    Process.exit(producer, :kill)

    assert_receive {:DOWN, ^session_ref, :process, ^session, :normal}
    assert eventually(fn -> PresenterSync.whereis(name) == nil end)
  end

  test "subscribers receive only increasing revisions and can request the cached state" do
    name = unique_name()
    producer = start_producer(self())

    assert {:ok, session} = PresenterSync.start_presentation(name, producer)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 0}}

    assert {:ok, ^session} = PresenterSync.subscribe(name)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 1}}

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_state_request, ^session, subscriber}}

    assert subscriber == self()

    assert :ok = PresenterSync.publish(session, 1, %{slide_index: :unauthorized})
    refute_receive {:easy_breezy_presentation_state, ^session, _, _}

    assert :ok = publish_from(producer, session, 1, %{slide_index: 0})

    assert_receive {:easy_breezy_presentation_state, ^session, 1, %{slide_index: 0}}

    assert :ok = publish_from(producer, session, 1, %{slide_index: 1})
    assert :ok = publish_from(producer, session, 0, %{slide_index: 2})
    refute_receive {:easy_breezy_presentation_state, ^session, _, _}

    assert :ok = publish_from(producer, session, 2, %{slide_index: 1})
    assert_receive {:easy_breezy_presentation_state, ^session, 2, %{slide_index: 1}}

    assert :ok =
             publish_from(producer, session, 3, %{slide_index: 1, elapsed_ms: 10_000})

    refute_receive {:easy_breezy_presentation_state, ^session, 3, _payload}

    assert :ok = PresenterSync.request_state(session)

    assert_receive {:easy_breezy_presentation_state, ^session, 3,
                    %{slide_index: 1, elapsed_ms: 10_000}}

    assert Session.latest(session) == {3, %{slide_index: 1, elapsed_ms: 10_000}}
  end

  test "commands are validated and accepted only from subscribers" do
    name = unique_name()
    producer = start_producer(self())

    assert {:ok, session} = PresenterSync.start_presentation(name, producer)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 0}}

    assert :ok = PresenterSync.command(session, :next)

    refute_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_command, ^session, _, _}}

    assert {:ok, ^session} = PresenterSync.subscribe(session)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 1}}

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_state_request, ^session, _subscriber}}

    assert :ok = PresenterSync.command(session, :reset_timer)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_command, ^session, subscriber, :reset_timer}}

    assert subscriber == self()

    assert :ok =
             PresenterSync.command(
               session,
               {:input, %{"key" => "x", "ctrlKey" => true, "untrusted" => "discarded"}}
             )

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_command, ^session, ^subscriber,
                     {:input, %{"key" => "x", "ctrlKey" => true}}}}

    assert :ok = PresenterSync.command(session, {:unknown, :command})

    refute_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_command, ^session, _, {:unknown, :command}}}
  end

  test "subscriber monitors update the producer with the current count" do
    name = unique_name()
    producer = start_producer(self())
    subscriber = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, session} = PresenterSync.start_presentation(name, producer)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 0}}

    assert {:ok, ^session} = PresenterSync.subscribe(session, subscriber)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 1}}

    assert Session.subscriber_count(session) == 1

    Process.exit(subscriber, :kill)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 0}}

    assert Session.subscriber_count(session) == 0
  end

  test "restarting the scoped pg process also resets the session supervisor" do
    name = unique_name()
    producer = start_producer(self())

    assert {:ok, session} = PresenterSync.start_presentation(name, producer)

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^session, 0}}

    old_scope = Process.whereis(Scope.name())
    old_session_supervisor = Process.whereis(SessionSupervisor)
    session_ref = Process.monitor(session)
    scope_ref = Process.monitor(old_scope)
    session_supervisor_ref = Process.monitor(old_session_supervisor)

    Process.exit(old_scope, :kill)

    assert_receive {:DOWN, ^scope_ref, :process, ^old_scope, :killed}
    assert_receive {:DOWN, ^session_ref, :process, ^session, :shutdown}

    assert_receive {:DOWN, ^session_supervisor_ref, :process, ^old_session_supervisor, :shutdown}

    assert eventually(fn ->
             new_scope = Process.whereis(Scope.name())
             is_pid(new_scope) and new_scope != old_scope
           end)

    assert eventually(fn ->
             new_session_supervisor = Process.whereis(SessionSupervisor)
             is_pid(new_session_supervisor) and new_session_supervisor != old_session_supervisor
           end)

    assert {:ok, replacement_session} = PresenterSync.ensure_presentation(name, producer)
    assert replacement_session != session

    assert_receive {:producer_message, ^producer,
                    {:easy_breezy_presenter_subscribers, ^replacement_session, 0}}
  end

  defp unique_name do
    {__MODULE__, System.unique_integer([:positive, :monotonic])}
  end

  defp start_producer(owner) do
    producer = spawn(fn -> producer_loop(owner) end)

    on_exit(fn ->
      if Process.alive?(producer), do: Process.exit(producer, :kill)
    end)

    producer
  end

  defp producer_loop(owner) do
    receive do
      {:publish, caller, session, revision, payload} ->
        result = PresenterSync.publish(session, revision, payload)
        send(caller, {:producer_published, self(), result})
        producer_loop(owner)

      message ->
        send(owner, {:producer_message, self(), message})
        producer_loop(owner)
    end
  end

  defp publish_from(producer, session, revision, payload) do
    send(producer, {:publish, self(), session, revision, payload})

    receive do
      {:producer_published, ^producer, result} -> result
    after
      1_000 -> :timeout
    end
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      receive do
      after
        10 -> eventually(fun, attempts - 1)
      end
    end
  end

  defp eventually(_fun, 0), do: false
end
