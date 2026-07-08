defmodule EasyBreezy.Examples.BreezeDeck do
  alias EasyBreezy.{Deck, Slide}

  Code.require_file("counter.ex", __DIR__)

  def deck do
    %Deck{
      title: "Breeze",
      slides: [
        %Slide{
          id: :title,
          title: "Breeze",
          layout: :title,
          payload: %{
            title: "Breeze",
            subtitle: "LiveView-style terminal apps in Elixir",
            speaker: "Gazler",
            footer: "Terminal-native slides",
            notes: "Rememeber to allow SSH access with a hex color, guess the colors."
          },
          steps: 0,
          transition: :slide
        },
        %Slide{
          id: :why,
          title: "Why Breeze",
          layout: :bullets,
          payload: %{
            notes: "lol",
            title: "Why Breeze",
            items: [
              "Server-driven UI fits the terminal surprisingly well.",
              "State, input, and rendering stay inside a single Elixir process model.",
              "The same primitives can power tools, dashboards, and presentations.",
              "A deck app is a good stress test because it mixes layout, navigation, and polish."
            ]
          },
          steps: 3,
          transition: :slide
        },
        %Slide{
          id: :image,
          title: "Images",
          layout: :two_column,
          payload: &image_payload/2,
          steps: 0,
          transition: :slide,
          disable_transitions?: true
        },
        %Slide{
          id: :anatomy,
          title: "Anatomy of a Breeze App",
          layout: :two_column,
          payload: %{
            title: "Anatomy of a Breeze App",
            left_title: "Runtime pieces",
            left_items: [
              "A Breeze.View owns state and events.",
              "Breeze.Server handles terminal IO and resize.",
              "Implicit modules add behavior like scroll, tabs, and input."
            ],
            right_title: "Minimal view",
            right_notice: "Advance once more for the code view.",
            right_lines: [
              "defmodule Talk do",
              "  use Breeze.View",
              "",
              "  def mount(_opts, term) do",
              "    {:ok, assign(term, slide: 0)}",
              "  end",
              "",
              "  def render(assigns) do",
              "    ~H\"\"\"",
              "    <box>slide {@slide}</box>",
              "    \"\"\"",
              "  end",
              "end"
            ]
          },
          steps: 3,
          transition: :slide
        },
        %Slide{
          id: :presenter,
          title: "Presenter Mode",
          layout: :presenter,
          payload: %{
            title: "Presenter Mode",
            items: [
              "The audience view stays clean and full-screen.",
              "The presenter can keep notes in-band in another pane.",
              "A timer and next-slide preview remove guesswork."
            ],
            notes: [
              "Mention that p toggles the footer into presenter mode.",
              "Notes do not need a second process if a single terminal is enough.",
              "A second-screen transport could be added later."
            ]
          },
          steps: 2,
          transition: :slide
        },
        %Slide{
          id: :mermaid,
          title: "Mermaid Component",
          layout: :two_column,
          payload: %{
            title: "Mermaid Component",
            left_title: "Source",
            left_lines: [
              "flowchart TD",
              "  classDef otpcolor color:#00ff66",
              "  breeze --> back_breeze",
              "  back_breeze --> termite",
              "  termite --> otp:::otpcolor",
              "  termite --> kino",
              "  termite --> ssh"
            ],
            right_title: "Terminal render",
            right_mode: :mermaid,
            right_mermaid_source: """
            flowchart TD
              classDef otpcolor color:#00ff66
              breeze --> back_breeze
              back_breeze --> termite
              termite --> otp:::otpcolor
              termite --> kino
              termite --> ssh
            """
          },
          transition: :slide
        },
        %Slide{
          id: :mermaid_shapes,
          title: "Mermaid Shapes",
          layout: :two_column,
          payload: %{
            title: "Mermaid Shapes",
            left_title: "Source",
            left_lines: [
              "flowchart TD",
              "  start(Start) --> check{Ready?}",
              "  check -->|yes| ship(Ship it)",
              "  check -->|no| revise[Revise]"
            ],
            right_title: "Terminal render",
            right_mode: :mermaid,
            right_mermaid_source: """
            flowchart TD
              start(Start) --> check{Ready?}
              check -->|yes| ship(Ship it)
              check -->|no| revise[Revise]
            """
          },
          transition: :slide
        },
        %Slide{
          id: :code,
          title: "Code Slides",
          layout: :code,
          payload: %{
            title: "Code Slides",
            code_language: "elixir",
            code_source: File.read!(Path.expand("counter.ex", __DIR__)),
            code_path: "examples/counter.ex",
            code_focus_ranges: [
              [],
              [{4, 6}],
              [{8, 14}],
              [{17, 19}, {21, 23}]
            ]
          },
          transition: :slide
        },
        %Slide{
          id: :counter_demo,
          title: "Counter Demo",
          layout: :breeze,
          payload: %{
            view: Counter
          },
          transition: :slide_up
        },
        %Slide{
          id: :performance,
          title: "What Still Hurts",
          layout: :bullets,
          payload: %{
            title: "What Still Hurts",
            items: [
              "Transitions make frame cost visible because they redraw the whole slide body.",
              "Large terminals amplify layout work and terminal writes.",
              "Profiling render and flush cost is the next step before polishing motion further."
            ]
          },
          steps: 2,
          transition: :slide_up
        }
      ]
    }
  end

  defp image_payload(body_width, _step) do
    left_width = max(div(body_width, 2) - 4, 16)
    path = Path.expand("image.png", __DIR__)

    %{
      title: "Images",
      left_lines:
        image_text_lines(
          "This uses the Kitty graphics protocol through Breeze overlays.",
          path,
          left_width
        ),
      right_mode: :image,
      right_path: path
    }
  end

  defp image_text_lines(caption, path, width) do
    lines = [
      {"text-secondary", "Ghostty/Kitty image experiment"},
      {"", ""},
      {"", caption},
      {"", ""},
      {"text-muted", "If your terminal ignores Kitty graphics, this slide falls back to text."},
      {"text-muted", "Image path:"}
    ]

    wrapped_lines =
      lines
      |> Enum.flat_map(fn {class, text} ->
        text
        |> wrap_paragraph(width)
        |> Enum.map(&{class, &1})
      end)

    wrapped_lines ++ Enum.map(wrap_code_line(path, width), &{"text-muted", &1})
  end

  defp wrap_code_line("", _width), do: [""]

  defp wrap_code_line(line, width) do
    line
    |> String.graphemes()
    |> Enum.chunk_every(max(width, 1))
    |> Enum.map(&Enum.join/1)
  end

  defp wrap_paragraph("", _width), do: [""]

  defp wrap_paragraph(text, width) do
    text
    |> String.split()
    |> Enum.flat_map(fn word ->
      if String.length(word) > max(width, 1), do: wrap_code_line(word, width), else: [word]
    end)
    |> wrap_words(max(width, 1))
  end

  defp wrap_words([], _width), do: []

  defp wrap_words(words, width) do
    {lines, current} =
      Enum.reduce(words, {[], ""}, fn word, {lines, current} ->
        cond do
          current == "" ->
            {lines, word}

          String.length(current <> " " <> word) <= width ->
            {lines, current <> " " <> word}

          true ->
            {[current | lines], word}
        end
      end)

    Enum.reverse([current | lines])
  end
end

EasyBreezy.run(
  deck: {EasyBreezy.Examples.BreezeDeck, :deck, []},
  themes: [:system16, :system, :nebula, :catppuccin, :dracula, :gruvbox, :nord, :solarized_light]
)
