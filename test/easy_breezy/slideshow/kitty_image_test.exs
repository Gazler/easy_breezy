defmodule EasyBreezy.Slideshow.KittyImageTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Slideshow.KittyImage

  test "places the image overlay at the bordered content origin" do
    box = %{id: "slide-image"}
    state = %{active?: true, mode: "show", command: "image-command"}
    context = %{layout: %{left: 10, top: 5}}

    assert {:ok, ^box, overlays: [overlay]} = KittyImage.animate(:root, box, [], state, context)
    assert overlay == %{x: 11, y: 6, content: "image-command"}
  end
end
