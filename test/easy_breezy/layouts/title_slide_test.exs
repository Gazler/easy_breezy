defmodule EasyBreezy.Layouts.TitleSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

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

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")
end
