defmodule EasyBreezy.Layouts.BulletsSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  test "renders trailing markdown after all bullets are visible" do
    before_markdown =
      render_bullets!(
        step: 1,
        after_markdown: "Final **note** with `code`."
      )

    assert before_markdown =~ "• One"
    assert before_markdown =~ "• Two"
    assert before_markdown =~ "[more]"
    refute before_markdown =~ "Final note with code."

    after_markdown =
      render_bullets!(
        step: 2,
        after_markdown: "Final **note** with `code`."
      )

    assert after_markdown =~ "• One"
    assert after_markdown =~ "• Two"
    refute after_markdown =~ "[more]"
    assert after_markdown =~ "Final note with code."
  end

  test "renders mermaid fences in trailing markdown" do
    rendered =
      render_bullets!(
        step: 2,
        after_markdown: """
        ```mermaid
        flowchart TD
          Markdown --> Mermaid
          Mermaid --> Terminal
        ```
        """
      )

    assert rendered =~ "┌──────────┐"
    assert rendered =~ "│ Markdown │"
    assert rendered =~ "│ Terminal │"
  end

  defp render_bullets!(opts) do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {84, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck: deck(Keyword.fetch!(opts, :after_markdown)),
          themes: [:nebula],
          theme: :nebula,
          step: Keyword.fetch!(opts, :step)
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    session
    |> Breeze.Test.render!()
    |> strip_ansi()
  end

  defp deck(after_markdown) do
    %Deck{
      title: "Bullets Deck",
      slides: [
        %Slide{
          id: :bullets,
          title: "Bullets",
          layout: :bullets,
          payload: %{
            title: "Bullets",
            items: ["One", "Two"],
            after_markdown: after_markdown
          },
          steps: 2
        }
      ]
    }
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")
end
