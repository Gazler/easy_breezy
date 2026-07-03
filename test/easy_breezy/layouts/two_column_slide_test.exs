defmodule EasyBreezy.Layouts.TwoColumnSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

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

    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {100, 30},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, themes: [:nebula], theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert Breeze.Test.render!(session) =~ "Images"
  end
end
