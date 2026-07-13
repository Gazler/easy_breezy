defmodule EasyBreezy.Layouts.ImageSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  test "fills the slide body without the bordered image inset" do
    path = Path.join(System.tmp_dir!(), "easy_breezy_full_image_slide.png")
    File.write!(path, "image-command")

    deck = %Deck{
      title: "Image Deck",
      slides: [
        %Slide{
          id: :full_image,
          title: "Full image",
          layout: :image,
          payload: %{path: path, alt: "Full image fallback"}
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

    assert Breeze.Test.render!(session) =~ "Full image fallback"

    assert {_module, state} = Breeze.Test.metadata(session).implicit_state["slide-image"]
    assert state.active?
    assert state.inset == 0
    assert state.scope == "presentation:full"

    {:ok, _acc, _box, decorations} = Breeze.ChildServer.render_snapshot(session.pid, [])
    decoration = Enum.find(decorations, &(&1.id == "slide-image"))

    assert {:ok, _box, overlays: [overlay]} =
             decoration.mod.animate(:root, decoration.box, decoration.flags, decoration.state, %{
               phase: :async,
               frame: 0,
               layout: decoration.layout
             })

    assert overlay.x == decoration.layout.left
    assert overlay.y == decoration.layout.top
    assert overlay.width == decoration.layout.width
    assert overlay.height == decoration.layout.height
  end

  test "centers explicit dimensions and scales them proportionally to fit" do
    path = Path.join(System.tmp_dir!(), "easy_breezy_centered_image_slide.png")
    File.write!(path, "image-command")

    deck = %Deck{
      title: "Image Deck",
      slides: [
        %Slide{
          id: :centered_image,
          title: "Centered image",
          layout: :image,
          payload: %{path: path, width: 72, height: 36}
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

    Breeze.Test.render!(session)

    {:ok, _acc, _box, decorations} =
      Breeze.ChildServer.render_snapshot(session.pid, terminal: session.terminal)

    decoration = Enum.find(decorations, &(&1.id == "slide-image"))

    assert decoration.layout.width == 54
    assert decoration.layout.height == 27
    assert decoration.layout.left == 23
    assert decoration.layout.top == 2
  end
end
