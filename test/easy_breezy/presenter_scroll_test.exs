defmodule EasyBreezy.PresenterScrollTest do
  use ExUnit.Case, async: true

  alias Breeze.Implicit.Scroll
  alias Breeze.Viewport
  alias EasyBreezy.PresenterScroll

  test "applies arrow-key scrolling to every scroll implicit" do
    viewport = %Viewport{height: 4, viewport_height: 4, content_height: 20}

    term = %{
      implicit_state: %{
        "left" => {Scroll, %{offset_y: 0}},
        "right" => {Scroll, %{offset_y: 2}}
      },
      elements: %{
        "left" => viewport,
        "right" => viewport
      }
    }

    term = PresenterScroll.apply(term, %{"key" => "ArrowDown"})

    assert scroll_offset(term, "left") == 1
    assert scroll_offset(term, "right") == 3
  end

  test "exports and imports scroll offsets" do
    term = %{
      implicit_state: %{
        "slide-bullets" => {Scroll, %{offset_y: 5, autoscroll: nil, pinned_bottom: false}},
        "other" => {SomeOtherImplicit, %{offset_y: 99}}
      }
    }

    assert PresenterScroll.export(term) == %{
             "slide-bullets" => %{offset_y: 5, autoscroll: nil, pinned_bottom: false}
           }

    imported =
      PresenterScroll.import(%{implicit_state: %{}}, %{
        "slide-bullets" => %{offset_y: 5, autoscroll: nil, pinned_bottom: false}
      })

    assert scroll_offset(imported, "slide-bullets") == 5
  end

  defp scroll_offset(term, id) do
    {Scroll, state} = term.implicit_state[id]
    state.offset_y
  end
end
