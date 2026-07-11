defmodule EasyBreezy.BreezeSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  defmodule CounterView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 0)}

    def render(assigns) do
      ~H"""
      <box class="width-full height-full">
        <box class="bold text-primary">Counter</box>
        <box>value: {@count}</box>
      </box>
      """
    end

    def handle_event(_, %{"key" => "ArrowUp"}, term) do
      {:noreply, assign(term, count: term.assigns.count + 1)}
    end

    def handle_event(_, _event, term), do: {:noreply, term}
  end

  defmodule ListView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, assign(term, selected: nil)}

    def render(assigns) do
      ~H"""
      <box>
        <.list id="languages" br-change="change">
          <:item value="elixir">Elixir</:item>
          <:item value="erlang">Erlang</:item>
        </.list>
        <box :if={@selected}>Selected: {@selected}</box>
      </box>
      """
    end

    def handle_event("change", %{value: value}, term),
      do: {:noreply, assign(term, selected: value)}

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "renders an interactive Breeze view inside a slide" do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {80, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: deck(),
          themes: [:nebula],
          theme: :nebula
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render!(session) =~ "value: 0"

    assert {:noreply, focused, true} = Breeze.Test.input(session, "ArrowUp")
    assert focused in ["breeze-slide-counter", "breeze-slide-counter::counter"]
    assert Breeze.Test.render!(session) =~ "value: 1"

    assert {:noreply, "breeze-slide-counter", true} = Breeze.Test.input(session, "ArrowUp")

    assert Breeze.Test.render!(session) =~ "value: 2"
  end

  test "focuses an element within an interactive Breeze slide" do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {80, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: focused_deck(),
          themes: [:nebula],
          theme: :nebula
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render!(session) =~ "Elixir"

    assert {:noreply, "breeze-slide-list::languages", true} =
             Breeze.Test.input(session, "ArrowDown")

    assert Breeze.Test.render!(session) =~ "Selected: elixir"
  end

  defp deck do
    %Deck{
      title: "Breeze Slide",
      slides: [
        %Slide{
          id: :counter,
          title: "Counter",
          layout: :breeze,
          payload: CounterView,
          disable_transitions?: true
        }
      ]
    }
  end

  defp focused_deck do
    %Deck{
      title: "Focused Breeze Slide",
      slides: [
        %Slide{
          id: :list,
          title: "List",
          layout: :breeze,
          payload: %{view: ListView, breeze_focus: "languages"},
          disable_transitions?: true
        }
      ]
    }
  end
end
