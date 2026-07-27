defmodule EasyBreezy.Export.HTMLTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Export.{Document, Frame, HTML, Media, Run, Style}

  test "renders compact reusable styles, embedded media, and browser navigation" do
    background = {13, 33, 55}
    text_style = %Style{foreground: {214, 231, 255}, background: background, bold: true}
    blank_style = %Style{background: background}

    runs = [
      %Run{x: 0, y: 0, width: 6, text: "<Deck>", style: text_style},
      %Run{x: 0, y: 1, width: 37, text: String.duplicate(" ", 37), style: blank_style}
    ]

    media = %Media{
      x: 2,
      y: 2,
      width: 4,
      height: 3,
      mime_type: "image/png",
      data: <<137, 80, 78, 71>>,
      alt: ~s(A "quoted" image)
    }

    frame = %Frame{
      width: 20,
      height: 5,
      background: background,
      slide_index: 0,
      step: 0,
      runs: runs,
      media: [media]
    }

    document = %Document{title: "A <Deck>", width: 20, height: 5, frames: [frame, frame]}

    assert {:ok, html} = HTML.render(document, [])

    assert html =~ "Cascadia+Mono:wght@400;700&amp;display=swap"
    assert html =~ ~s(font-family: "Cascadia Mono", monospace)
    assert html =~ "&lt;Deck&gt;"
    assert html =~ "A &quot;quoted&quot; image"
    assert html =~ "data:image/png;base64,iVBORw=="
    assert html =~ ~s(class="r s)
    assert html =~ ~s(data-s="0" data-p="0")
    assert html =~ "document.fonts?.ready.then(fit)"

    assert length(Regex.scan(~r/font-weight: 700/, html)) == 1
    refute html =~ String.duplicate(" ", 37)
  end

  test "rejects empty documents" do
    document = %Document{title: "Empty", width: 1, height: 1, frames: []}
    assert HTML.render(document, []) == {:error, :empty_document}
  end
end
