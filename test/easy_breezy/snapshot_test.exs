defmodule EasyBreezy.SnapshotTest do
  use ExUnit.Case, async: false
  use Breeze.SnapshotAssertions

  alias EasyBreezy.{Deck, Slide}

  setup do
    session =
      start_slideshow!(
        deck: deck_with(title_slide()),
        size: {100, 24}
      )

    on_exit(fn -> Breeze.Test.stop(session) end)
    {:ok, session: session}
  end

  test "title slide smoke snapshot", %{session: session} do
    assert_snapshot(Breeze.Test.render!(session), "easy_breezy/title_slide.ansi")
  end

  test "bullets slide smoke snapshot" do
    session =
      start_slideshow!(
        deck: deck_with(bullets_slide()),
        size: {100, 24}
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "easy_breezy/bullets_slide.ansi")
  end

  test "two column slide smoke snapshot" do
    session =
      start_slideshow!(
        deck: deck_with(two_column_slide()),
        size: {100, 24}
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "easy_breezy/two_column_slide.ansi")
  end

  test "presenter slide smoke snapshot" do
    session =
      start_slideshow!(
        deck: deck_with(presenter_slide()),
        size: {100, 24}
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "easy_breezy/presenter_slide.ansi")
  end

  test "code slide smoke snapshot" do
    session =
      start_slideshow!(
        deck: deck_with(code_slide()),
        size: {100, 24},
        start_opts: [step: 1]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "easy_breezy/code_slide.ansi")
  end

  test "code slide wrapped line snapshot" do
    session =
      start_slideshow!(
        deck: deck_with(code_slide_with_wrapped_line()),
        size: {100, 24},
        start_opts: [step: 1]
      )

    on_exit(fn -> Breeze.Test.stop(session) end)

    assert_snapshot(Breeze.Test.render!(session), "easy_breezy/code_slide_wrapped.ansi")
  end

  defp start_slideshow!(opts) do
    {extra_start_opts, test_opts} = Keyword.pop(opts, :start_opts, [])

    Breeze.Test.start!(EasyBreezy.Slideshow,
      size: Keyword.get(test_opts, :size, {100, 24}),
      theme: Breeze.Theme.builtin(:nebula),
      start_opts:
        [
          deck: Keyword.fetch!(test_opts, :deck),
          themes: [:nebula, :gruvbox, :nord],
          theme: :nebula
        ] ++ extra_start_opts
    )
  end

  defp deck_with(slide) do
    %Deck{
      title: "Smoke Test Deck",
      slides: [slide]
    }
  end

  defp title_slide do
    %Slide{
      id: :title,
      title: "Title",
      layout: :title,
      payload: %{
        title: "Easy Breezy",
        subtitle: "Slide smoke tests",
        speaker: "Gazler",
        footer: "Built on Breeze"
      }
    }
  end

  defp bullets_slide do
    %Slide{
      id: :bullets,
      title: "Bullets",
      layout: :bullets,
      payload: %{
        title: "Why It Exists",
        items: [
          "Layouts should render without crashing.",
          "Snapshots should catch obvious regressions.",
          "Each layout gets a small smoke test."
        ]
      },
      steps: 2
    }
  end

  defp two_column_slide do
    %Slide{
      id: :two_column,
      title: "Two Column",
      layout: :two_column,
      payload: %{
        title: "Split Layout",
        left_title: "Left",
        left_items: [
          "Bullets still work here.",
          "Text rendering should wrap cleanly."
        ],
        right_title: "Right",
        right_notice: nil,
        right_lines: [
          "defmodule Sample do",
          "  def ok?, do: true",
          "end"
        ]
      },
      steps: 1
    }
  end

  defp presenter_slide do
    %Slide{
      id: :presenter,
      title: "Presenter",
      layout: :presenter,
      payload: %{
        title: "Presenter Mode",
        items: [
          "Audience content stays clean.",
          "Notes stay visible to the speaker."
        ],
        notes: [
          "Mention the timer.",
          "Mention the next slide preview."
        ]
      },
      steps: 1
    }
  end

  defp code_slide do
    %Slide{
      id: :code,
      title: "Code",
      layout: :code,
      payload: %{
        title: "Code Slide",
        code_language: "elixir",
        code_source: """
        defmodule Counter do
          use Breeze.View

          def mount(_opts, term) do
            {:ok, assign(term, count: 0)}
          end

          def render(assigns) do
            ~H\"\"\"
            <box>{@count}</box>
            \"\"\"
          end
        end
        """,
        code_path: "examples/counter.ex",
        code_focus_ranges: [{4, 10}]
      },
      steps: 1
    }
  end

  defp code_slide_with_wrapped_line do
    %Slide{
      id: :code_wrapped,
      title: "Code Wrapped",
      layout: :code,
      payload: %{
        title: "Wrapped Code Slide",
        code_language: "elixir",
        code_source: """
        defmodule WrappedCounter do
          def render_label(count), do: "count=\#{count} value=\#{count * 10} status=running mode=wrap-check theme=nebula border=dimmed background=stable"
        end
        """,
        code_path: "examples/wrapped_counter.ex",
        code_focus_ranges: [2]
      },
      steps: 1
    }
  end
end
