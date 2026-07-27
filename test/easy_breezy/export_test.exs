defmodule EasyBreezy.ExportTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias EasyBreezy.{Deck, Slide}
  alias EasyBreezy.Export.{Frame, HTML, Media}

  defmodule InitialCounter do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 0)}

    def render(assigns) do
      ~H"""
      <box class="width-full height-full bg">
        <box class="bold text-primary">Snapshot counter</box>
        <box>value: {@count}</box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
  end

  defmodule UnavailableView do
    use Breeze.View

    def mount(_opts, _term), do: raise("fixture dependency is unavailable")
    def render(_assigns), do: ""
  end

  test "captures every reveal, embedded images, and a live slide's initial state" do
    image_path = Path.expand("../../examples/image.png", __DIR__)

    deck = %Deck{
      title: "Export fixture",
      slides: [
        %Slide{
          id: :bullets,
          title: "Reveals",
          layout: :bullets,
          steps: 1,
          disable_transitions?: true,
          payload: %{title: "Reveals", items: ["First", "Second"]}
        },
        %Slide{
          id: :image,
          title: "Image",
          layout: :image,
          disable_transitions?: true,
          payload: %{path: image_path, alt: "Fixture image"}
        },
        %Slide{
          id: :counter,
          title: "Counter",
          layout: :breeze,
          disable_transitions?: true,
          payload: InitialCounter
        }
      ]
    }

    assert {:ok, document} =
             EasyBreezy.Export.capture(deck, theme: :nebula, size: {80, 24})

    assert document.title == "Export fixture"
    assert document.metadata.theme == :nebula

    assert Enum.map(document.frames, &{&1.slide_id, &1.step}) == [
             {:bullets, 0},
             {:bullets, 1},
             {:image, 0},
             {:counter, 0}
           ]

    image_frame = Enum.find(document.frames, &(&1.slide_id == :image))
    assert [%Media{mime_type: "image/png", source: ^image_path}] = image_frame.media

    counter_frame = Enum.find(document.frames, &(&1.slide_id == :counter))
    assert counter_frame.metadata == %{layout: :breeze, live?: true}
    assert Frame.plain_text(counter_frame) =~ "value: 0"

    assert {:ok, html} = HTML.render(document, font_stylesheet: nil)
    assert html =~ "data:image/png;base64,"
    assert html =~ "value: 0"
    refute html =~ "fonts.googleapis.com"
  end

  test "captures with a named custom theme" do
    theme_source = Breeze.Theme.builtin(:nord)
    theme = {:brand, theme_source}

    deck = %Deck{
      title: "Named theme",
      slides: [
        %Slide{
          id: :title,
          title: "Branded",
          layout: :title,
          disable_transitions?: true,
          payload: %{title: "Branded"}
        }
      ]
    }

    assert {:ok, document} =
             EasyBreezy.Export.capture(deck, theme: theme, size: {80, 24})

    assert document.metadata.theme == theme
    assert [frame] = document.frames
    assert frame.background == Breeze.Theme.color(theme_source, :surface)
    assert Frame.plain_text(frame) =~ "Named theme"
  end

  test "preserves each requested step in live slide placeholders" do
    deck = %Deck{
      title: "Unavailable live slide",
      slides: [
        %Slide{
          id: :unavailable,
          title: "Unavailable",
          layout: :breeze,
          steps: 2,
          disable_transitions?: true,
          payload: UnavailableView
        }
      ]
    }

    assert {:ok, document} = capture_without_log(deck, theme: :nord, steps: :all)

    assert Enum.map(document.frames, &{&1.slide_index, &1.step}) == [
             {0, 0},
             {0, 1},
             {0, 2}
           ]

    assert Enum.all?(document.frames, fn frame ->
             frame.metadata.live? and
               frame.metadata.snapshot == :unavailable and
               Frame.plain_text(frame) =~
                 "Its initial state was unavailable while exporting."
           end)

    assert {:ok, last_document} = capture_without_log(deck, theme: :nord, steps: :last)
    assert [%{slide_index: 0, step: 2}] = last_document.frames
  end

  defp capture_without_log(deck, opts) do
    {result, _log} = with_log(fn -> EasyBreezy.Export.capture(deck, opts) end)
    result
  end
end
