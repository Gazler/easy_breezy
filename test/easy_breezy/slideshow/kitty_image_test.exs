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

  test "supports an edge-to-edge placement with no inset" do
    box = %{id: "slide-image"}
    path = Path.join(System.tmp_dir!(), "easy_breezy_kitty_full_image_test.img")
    File.write!(path, "image-command")
    context = %{layout: %{left: 10, top: 5, width: 20, height: 9}}
    state = %{active?: true, mode: "show", path: path, scope: "presentation:full", inset: 0}

    assert {:ok, ^box, overlays: [overlay]} =
             KittyImage.animate(:root, box, [], state, context)

    assert %{x: 10, y: 5, width: 20, height: 9} = overlay
    assert overlay.content =~ "c=20,r=9"
  end

  test "chunks large image payloads without building character lists" do
    box = %{id: "slide-image"}
    path = Path.join(System.tmp_dir!(), "easy_breezy_kitty_chunked_image_test.img")
    File.write!(path, :binary.copy(<<1>>, 3_100))
    context = %{layout: %{left: 0, top: 0, width: 20, height: 9}}
    state = %{active?: true, mode: "show", path: path, scope: "presentation:full"}

    assert {:ok, ^box, overlays: [%{content: command}]} =
             KittyImage.animate(:root, box, [], state, context)

    assert length(:binary.matches(command, "\e_G")) == 3
    assert command =~ ",m=1;"
    assert command =~ "\e_Gq=2,m=0;"
  end

  test "rejects source images over the size limit" do
    box = %{id: "slide-image"}
    path = Path.join(System.tmp_dir!(), "easy_breezy_kitty_oversized_image_test.img")

    {:ok, file} = :file.open(path, [:write, :binary])
    {:ok, _position} = :file.position(file, 64 * 1024 * 1024)
    :ok = :file.write(file, <<0>>)
    :ok = :file.close(file)

    context = %{layout: %{left: 0, top: 0, width: 20, height: 9}}
    state = %{active?: true, mode: "show", path: path, scope: "presentation:full"}

    assert KittyImage.animate(:root, box, [], state, context) == box
  end

  test "decodes GIFs into terminal-driven Kitty animation frames" do
    gif =
      Base.decode64!(
        "R0lGODlhAgABAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQABQAAACwAAAAAAgABAAACAgQKACH5BAAKAAAALAAAAAACAAEAgAAA/wAAAAICBAoAOw=="
      )

    box = %{id: "slide-image"}
    path = Path.join(System.tmp_dir!(), "easy_breezy_kitty_animation.gif")
    File.write!(path, gif)
    context = %{layout: %{left: 10, top: 5, width: 20, height: 9}}
    state = %{active?: true, mode: "show", path: path, scope: "presentation:full", inset: 0}

    assert {:ok, ^box, overlays: [%{content: command}]} =
             KittyImage.animate(:root, box, [], state, context)

    assert command =~ "a=T,f=100"
    assert command =~ "a=f,f=100"
    assert command =~ "z=100,X=1"
    assert command =~ "a=a,i="
    assert command =~ "r=1,z=50"
    assert command =~ "s=3,v=1"
  end

  test "uses timed frame retransmission for client-driven GIF animation" do
    gif =
      Base.decode64!(
        "R0lGODlhAgABAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQABQAAACwAAAAAAgABAAACAgQKACH5BAAKAAAALAAAAAACAAEAgAAA/wAAAAICBAoAOw=="
      )

    path = Path.join(System.tmp_dir!(), "easy_breezy_kitty_client_animation.gif")
    File.write!(path, gif)

    assert {:ok, state, rerender_every: 25} =
             KittyImage.init(
               [],
               %{
                 :"image-path" => path,
                 :"image-active" => true,
                 :"image-animation-mode" => "client",
                 :"image-scope" => "presentation:full"
               },
               %{}
             )

    assert state.animation_transport == :client

    box = %{id: "slide-image"}

    context = %{
      id: "slide-image",
      layout: %{left: 10, top: 5, width: 20, height: 9},
      now_ms: state.animation_started_at_ms + 25
    }

    assert {:ok, ^box, overlays: [first]} =
             KittyImage.animate(:root, box, [], state, context)

    assert {:ok, ^box, overlays: [second]} =
             KittyImage.animate(:root, box, [], state, %{
               context
               | now_ms: state.animation_started_at_ms + 75
             })

    assert first.patch_only
    assert second.patch_only
    assert first.content != second.content
    assert first.content =~ "a=T,f=100"
    assert second.content =~ "a=T,f=100"
    refute first.content =~ "a=f,f=100"
    refute second.content =~ "a=f,f=100"
  end
end
