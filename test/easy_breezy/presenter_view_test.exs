defmodule EasyBreezy.PresenterViewTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  defmodule RecordingTerminal do
    def write(%{owner: owner} = term, output) do
      send(owner, {:terminal_write, output})
      {:ok, term}
    end
  end

  test "cleans up kitty images when presenter state leaves an image slide" do
    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        terminal: recording_terminal(self()),
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: text_deck(), theme: :nebula, alt_screen: false]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    Breeze.Test.info(
      session,
      {:easy_breezy_presentation_state, presentation_payload(image_deck(), 0)}
    )

    refute_receive {:terminal_write, _}

    Breeze.Test.info(
      session,
      {:easy_breezy_presentation_state, presentation_payload(image_deck(), 1)}
    )

    assert_receive {:terminal_write, output}
    assert output == EasyBreezy.Slideshow.KittyImage.delete_command()
  end

  test "caps the next preview frame at the presentation width" do
    deck = preview_deck()

    session =
      Breeze.Test.start!(EasyBreezy.PresenterView,
        size: {250, 70},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [deck: deck, theme: :nebula]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    payload =
      deck
      |> presentation_payload(0)
      |> Map.merge(%{screen_width: 86, screen_height: 23})

    Breeze.Test.info(session, {:easy_breezy_presentation_state, payload})

    rendered = Breeze.Test.render!(session)
    plain = strip_ansi(rendered)

    assert plain =~ "Next: Why Breeze"

    assert plain =~
             "┌────────────────────────────────────────────────────────────────────────────────────┐ ┌Next: Why Breeze"
  end

  defp recording_terminal(owner) do
    %Termite.Terminal{
      adapter: {RecordingTerminal, %{owner: owner}},
      size: %{width: 100, height: 24}
    }
  end

  defp presentation_payload(deck, slide_index) do
    %{
      deck: deck,
      slide_index: slide_index,
      step: 0,
      screen_width: 100,
      screen_height: 24,
      theme_name: :nebula,
      actual_theme_mode: :custom,
      theme_status: :ready
    }
  end

  defp text_deck do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{id: :intro, title: "Intro", layout: :bullets, payload: text_payload("Intro")}
      ]
    }
  end

  defp image_deck do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{
          id: :image,
          title: "Image",
          layout: :two_column,
          payload:
            Map.merge(text_payload("Image"), %{right_mode: :image, right_path: "missing.png"})
        },
        %Slide{id: :outro, title: "Outro", layout: :bullets, payload: text_payload("Outro")}
      ]
    }
  end

  defp preview_deck do
    %Deck{
      title: "Presenter Test",
      slides: [
        %Slide{id: :title, title: "Title", layout: :bullets, payload: text_payload("Title")},
        %Slide{
          id: :why,
          title: "Why Breeze",
          layout: :bullets,
          payload: text_payload("Why Breeze")
        }
      ]
    }
  end

  defp text_payload(title), do: %{title: title, items: ["One"]}

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")
end
