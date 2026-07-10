defmodule EasyBreezy.Layouts.BulletsSlideTest do
  use ExUnit.Case, async: false

  alias EasyBreezy.{Deck, Slide}

  test "renders inline markdown in bullet items" do
    raw_rendered =
      render_bullets_raw!(
        step: 1,
        items: ["`lol` Dependency free", "- `otp` Runtime"]
      )

    rendered = strip_ansi(raw_rendered)

    assert raw_rendered =~ "\e[36mlol"
    assert raw_rendered =~ "\e[36motp"
    assert rendered =~ "• lol Dependency free"
    assert rendered =~ "• otp Runtime"
    refute rendered =~ "`lol`"
    refute rendered =~ "`otp`"
  end

  test "immediate reveal renders all bullets and trailing markdown at the first step" do
    rendered =
      render_bullets!(
        step: 0,
        steps: 0,
        reveal: :immediate,
        items: ["One", "Two"],
        after_markdown: "Final **note**."
      )

    assert rendered =~ "• One"
    assert rendered =~ "• Two"
    assert rendered =~ "Final note."
    refute rendered =~ "[more]"
  end

  test "step markers delay trailing markdown for immediate reveal slides" do
    first_step =
      render_bullets!(
        step: 0,
        steps: 1,
        reveal: :immediate,
        items: ["One", "Two"],
        after_markdown: """
        <!-- step -->

        Final **note**.
        """
      )

    assert first_step =~ "• One"
    assert first_step =~ "• Two"
    assert first_step =~ "[more]"
    refute first_step =~ "Final note."

    extra_step =
      render_bullets!(
        step: 1,
        steps: 1,
        reveal: :immediate,
        items: ["One", "Two"],
        after_markdown: """
        <!-- step -->

        Final **note**.
        """
      )

    assert extra_step =~ "• One"
    assert extra_step =~ "• Two"
    refute extra_step =~ "[more]"
    assert extra_step =~ "Final note."
  end

  test "step markers reveal trailing markdown progressively after bullets" do
    first_markdown_step =
      render_bullets!(
        step: 2,
        steps: 3,
        after_markdown: """
        First **note**.

        <!-- step -->

        Second **note**.
        """
      )

    assert first_markdown_step =~ "• One"
    assert first_markdown_step =~ "• Two"
    assert first_markdown_step =~ "First note."
    refute first_markdown_step =~ "Second note."
    assert first_markdown_step =~ "[more]"

    second_markdown_step =
      render_bullets!(
        step: 3,
        steps: 3,
        after_markdown: """
        First **note**.

        <!-- step -->

        Second **note**.
        """
      )

    assert second_markdown_step =~ "First note."
    assert second_markdown_step =~ "Second note."
    refute second_markdown_step =~ "[more]"
  end

  test "renders nested bullet items with their parent step" do
    raw_rendered =
      render_bullets_raw!(
        step: 0,
        items: ["Parent\n  - Child `code`", "Next"]
      )

    rendered = strip_ansi(raw_rendered)

    assert raw_rendered =~ "\e[36mcode"
    assert rendered =~ "• Parent"
    assert rendered =~ "  • Child code"
    refute rendered =~ "• Next"
    assert rendered =~ "[more]"
  end

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

  test "renders breeze fences in trailing markdown" do
    rendered =
      render_bullets!(
        step: 2,
        after_markdown: """
        ```breeze
        <box style="text-3 bg-5 bold">Hello World</box>
        ```
        """
      )

    assert rendered =~ "Hello World"
    refute rendered =~ "<box"
  end

  test "separates trailing code fences from following breeze fences" do
    rendered =
      render_bullets!(
        step: 2,
        after_markdown: """
        ```elixir
        IO.puts(:ok)
        ```
        ```breeze
        <box style="text-3 bg-5 bold">Hello World</box>
        ```
        """
      )

    assert rendered =~ "│IO.puts(:ok)"
    assert_blank_line_between(rendered, "IO.puts(:ok)", "Hello World")
  end

  test "renders non-elixir trailing code fences across the full slide width" do
    rendered =
      render_bullets_raw!(
        step: 2,
        after_markdown: """
        ```
        \\e[<0;12;7M  # press
        ```
        """
      )

    line =
      rendered
      |> String.split("\n", trim: false)
      |> Enum.find(&String.contains?(&1, "\\e[<0;12;7M"))

    assert line != nil
    assert line =~ "\e[48;2;31;70;98"

    refute Regex.match?(
             ~r/\e\[48;2;25;53;73;38;2;214;231;255m +\e\[0m\e\[48;2;25;53;73;38;2;\d+;\d+;\d+m│\e\[0m$/,
             line
           )
  end

  defp render_bullets!(opts) do
    opts
    |> render_bullets_raw!()
    |> strip_ansi()
  end

  defp render_bullets_raw!(opts) do
    session =
      Breeze.Test.start!(EasyBreezy.Slideshow,
        size: {84, 24},
        theme: Breeze.Theme.builtin(:nebula),
        start_opts: [
          deck:
            deck(
              Keyword.get(opts, :after_markdown),
              Keyword.get(opts, :items, ["One", "Two"]),
              Keyword.get(opts, :reveal),
              Keyword.get(opts, :steps, 2)
            ),
          themes: [:nebula],
          theme: :nebula,
          step: Keyword.fetch!(opts, :step)
        ]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    session
    |> Breeze.Test.render!()
  end

  defp deck(after_markdown, items, reveal, steps) do
    payload =
      %{
        title: "Bullets",
        items: items,
        after_markdown: after_markdown
      }
      |> maybe_put(:reveal, reveal)

    %Deck{
      title: "Bullets Deck",
      slides: [
        %Slide{
          id: :bullets,
          title: "Bullets",
          layout: :bullets,
          payload: payload,
          steps: steps
        }
      ]
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")

  defp assert_blank_line_between(text, before_fragment, after_fragment) do
    lines = String.split(text, "\n", trim: false)
    before_index = Enum.find_index(lines, &String.contains?(&1, before_fragment))
    after_index = Enum.find_index(lines, &String.contains?(&1, after_fragment))

    assert before_index != nil
    assert after_index != nil
    assert after_index == before_index + 2
  end
end
