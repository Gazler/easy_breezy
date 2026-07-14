defmodule EasyBreezy.RuntimeSupervisionTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.PresenterSync
  alias EasyBreezy.PresenterSync.Scope
  alias EasyBreezy.{Deck, Slide}

  test "the application owns presenter infrastructure but not terminal sessions" do
    children = Supervisor.which_children(EasyBreezy.Supervisor)

    assert {EasyBreezy.PresenterSync.Supervisor, presenter_supervisor, :supervisor, _modules} =
             List.keyfind(children, EasyBreezy.PresenterSync.Supervisor, 0)

    assert Process.alive?(presenter_supervisor)

    presentation = start_presentation(unique_name())
    on_exit(fn -> Breeze.Test.stop(presentation) end)

    refute Enum.any?(children, fn {_id, pid, _type, _modules} ->
             pid == presentation.pid
           end)
  end

  test "presentation and presenter reconnect after the scoped pg process restarts" do
    sync_name = unique_name()
    presentation = start_presentation(sync_name)
    Breeze.Test.render!(presentation)

    presenter =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck(), sync_name: sync_name, theme: :nebula]
      )

    on_exit(fn ->
      Breeze.Test.stop(presenter)
      Breeze.Test.stop(presentation)
    end)

    assert eventually(fn ->
             session = PresenterSync.whereis(sync_name)

             is_pid(session) and
               Breeze.Test.metadata(presentation).assigns.presenter_session_pid == session and
               Breeze.Test.metadata(presenter).assigns.presentation_pid == session
           end)

    old_session = PresenterSync.whereis(sync_name)
    old_scope = Process.whereis(Scope.name())
    Process.exit(old_scope, :kill)

    assert eventually(fn ->
             session = PresenterSync.whereis(sync_name)

             is_pid(session) and session != old_session and
               Breeze.Test.metadata(presentation).assigns.presenter_session_pid == session and
               Breeze.Test.metadata(presenter).assigns.presentation_pid == session and
               Breeze.Test.metadata(presenter).assigns.presentation_screen_width == 80
           end)
  end

  defp start_presentation(sync_name) do
    Breeze.Test.start!(EasyBreezy.Slideshow,
      size: {80, 24},
      theme: Breeze.Theme.builtin(:nebula),
      start_opts: [
        deck: deck(),
        presenter_mode: :presentation,
        sync_name: sync_name,
        themes: [:nebula],
        theme: :nebula
      ]
    )
  end

  defp deck do
    %Deck{
      title: "Runtime supervision",
      slides: [
        %Slide{
          id: :intro,
          title: "Intro",
          layout: :bullets,
          payload: %{title: "Intro", items: ["Supervised"]},
          disable_transitions?: true
        }
      ]
    }
  end

  defp unique_name do
    {__MODULE__, System.unique_integer([:positive, :monotonic])}
  end

  defp eventually(fun, attempts \\ 200)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
