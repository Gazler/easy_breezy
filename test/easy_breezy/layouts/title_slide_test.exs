defmodule EasyBreezy.Layouts.TitleSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  test "title slide renders an optional prefix above the title" do
    deck = %Deck{
      title: "Prefix Deck",
      slides: [
        %Slide{
          id: :title,
          title: "Title",
          layout: :title,
          payload: %{
            prefix: "Chapter 1",
            title: "Easy Breezy",
            subtitle: "Terminal slides",
            speaker: "Gazler",
            footer: "Built on Breeze"
          }
        }
      ]
    }

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {100, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    rendered =
      session
      |> Breeze.Test.render!()
      |> strip_ansi()

    assert rendered =~ "╚══════╝"
    assert rendered =~ "Terminal slides"
    assert rendered =~ "by Gazler"
    assert rendered =~ "Built on Breeze"

    lines = String.split(rendered, "\n")

    prefix_line = Enum.find_index(lines, &String.contains?(&1, "Chapter 1"))
    title_line = Enum.find_index(lines, &String.contains?(&1, "██"))

    assert is_integer(prefix_line)
    assert is_integer(title_line)
    assert title_line > prefix_line + 1
  end

  test "title slide payload can override the figlet font" do
    deck = %Deck{
      title: "Font Deck",
      slides: [
        %Slide{
          id: :title,
          title: "Title",
          layout: :title,
          payload: %{
            title: "Figlet Fonts",
            title_font: :future
          }
        }
      ]
    }

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {100, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    rendered =
      session
      |> Breeze.Test.render!()
      |> strip_ansi()

    assert rendered =~ "┏━╸╻┏━╸╻  ┏━╸╺┳╸   ┏━╸┏━┓┏┓╻╺┳╸┏━┓"
  end

  test "clicking the animated title does not crash" do
    deck = %Deck{
      title: "Mouse Deck",
      slides: [
        %Slide{
          id: :title,
          title: "Title",
          layout: :title,
          payload: %{title: "Breeze"}
        }
      ]
    }

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {80, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.render!(session)

    {_id, target} =
      session.pid
      |> Breeze.ChildServer.layout_snapshot()
      |> Map.fetch!(:mouse_targets)
      |> Enum.find(fn {id, _target} -> String.starts_with?(id, "title-gradient-") end)

    assert {:noreply, _focused, _consumed?} =
             Breeze.Test.input(session, %{
               "mouse" => %{
                 x: target.left + 1,
                 y: target.top + 1,
                 action: :press,
                 modifiers: [],
                 button: :left
               }
             })

    assert Breeze.Test.render!(session) =~ "Mouse Deck"
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")
end
