defmodule EasyBreezy.Slideshow.KittyImageTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Slideshow.KittyImage

  test "places the image overlay at the bordered content origin" do
    box = %{id: "slide-image"}
    path = Path.join(System.tmp_dir!(), "easy_breezy_kitty_image_test.img")
    File.write!(path, "image-command")
    state = %{active?: true, mode: "show", path: path, scope: "presenter-next:right"}
    context = %{layout: %{left: 10, top: 5, width: 20, height: 9}}

    assert {:ok, ^box, overlays: [overlay]} = KittyImage.animate(:root, box, [], state, context)

    assert %{
             x: 11,
             y: 6,
             width: 18,
             height: 7,
             content: command
           } = overlay

    assert command =~ "c=18,r=7"
  end

  test "uses the image scope to separate otherwise identical placements" do
    box = %{id: "slide-image"}
    path = Path.join(System.tmp_dir!(), "easy_breezy_kitty_image_scope_test.img")
    File.write!(path, "image-command")
    context = %{id: "slide-image", layout: %{left: 0, top: 0, width: 20, height: 9}}

    assert {:ok, _box, overlays: [current]} =
             KittyImage.animate(
               :root,
               box,
               [],
               %{active?: true, mode: "show", path: path, scope: "presenter-current:right"},
               context
             )

    assert {:ok, _box, overlays: [preview]} =
             KittyImage.animate(
               :root,
               box,
               [],
               %{active?: true, mode: "show", path: path, scope: "presenter-next:right"},
               context
             )

    assert current.image_id != preview.image_id
    assert current.placement_id != preview.placement_id
  end
end
