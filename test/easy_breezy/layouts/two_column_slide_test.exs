defmodule EasyBreezy.Layouts.TwoColumnSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  test "immediate reveal renders all left items and right text at the first step" do
    deck = %Deck{
      title: "Split Deck",
      slides: [
        %Slide{
          id: :split,
          title: "Split",
          layout: :two_column,
          payload: %{
            title: "Split",
            left_title: "Runtime",
            left_items: ["One", "Two"],
            reveal: :immediate,
            right_title: "Notes",
            right_notice: "Advance for notes",
            right_lines: ["Shown immediately"]
          },
          steps: 0
        }
      ]
    }

    rendered = render_deck!(deck) |> strip_ansi()

    assert rendered =~ "• One"
    assert rendered =~ "• Two"
    assert rendered =~ "Shown immediately"
    refute rendered =~ "Advance for notes"
  end

  test "renders inline markdown in left bullet items" do
    deck = %Deck{
      title: "Split Deck",
      slides: [
        %Slide{
          id: :split,
          title: "Split",
          layout: :two_column,
          payload: %{
            title: "Split",
            left_title: "Runtime",
            left_items: ["`lol` Dependency free"],
            right_title: "Notes",
            right_lines: ["Plain text"]
          }
        }
      ]
    }

    raw_rendered = render_deck!(deck)
    rendered = strip_ansi(raw_rendered)

    assert raw_rendered =~ "\e[36mlol"
    assert rendered =~ "• lol Dependency free"
    refute rendered =~ "`lol`"
  end

  test "renders nested left bullet items with their parent step" do
    deck = %Deck{
      title: "Split Deck",
      slides: [
        %Slide{
          id: :split,
          title: "Split",
          layout: :two_column,
          payload: %{
            title: "Split",
            left_title: "Runtime",
            left_items: ["Parent\n  - Child", "Next"],
            right_title: "Notes",
            right_lines: ["Plain text"]
          },
          steps: 1
        }
      ]
    }

    rendered = render_deck!(deck) |> strip_ansi()

    assert rendered =~ "• Parent"
    assert rendered =~ "  • Child"
    refute rendered =~ "• Next"
  end

  test "renders image payloads without optional column titles" do
    deck = %Deck{
      title: "Image Deck",
      slides: [
        %Slide{
          id: :image,
          title: "Images",
          layout: :two_column,
          payload: %{
            title: "Images",
            left_lines: [{"text-secondary", "Image explanation"}],
            right_mode: :image,
            right_path: "missing.png"
          }
        }
      ]
    }

    assert render_deck!(deck) =~ "Images"
  end

  defp render_deck!(deck) do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {100, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.render!(session)
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")
end
