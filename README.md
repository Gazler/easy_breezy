# EasyBreezy

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `easy_breezy` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:easy_breezy, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/easy_breezy>.

## HTML export

Export a Markdown deck at a fixed terminal size with an explicit Breeze theme:

```console
mix easy_breezy.export slides.md --theme nebula --output slides.html
```

Use `--require` for live slide modules. It accepts a file, a quoted wildcard,
or a shell-expanded wildcard, and can be repeated:

```console
mix easy_breezy.export ../elixirconf2026/markdown_slides.md \
  --theme nebula \
  --require '../elixirconf2026/code/*.ex' \
  --output slides.html
```

The exporter captures every slide reveal by default. Images are deduplicated
and embedded in the HTML, while repeated terminal styles and grid positions
are shared through compact CSS classes. Live slides are freshly mounted and
captured in their initial state. If a live view cannot mount in the exporting
environment, that frame becomes a themed placeholder instead of aborting the
rest of the deck.

The default viewport is `100x30`; override it with `--columns` and `--rows`.
Use `--steps first` or `--steps last` to export one state per slide instead of
all reveals. In the browser, use the arrow keys, Page Up/Page Down, Enter, or
Space to navigate; press `f` for fullscreen. URLs use `#slide.step` fragments.

The HTML backend uses Cascadia Mono at weights 400 and 700, matching Breeze's
documentation previews, and refits the deck after the webfont loads. Media,
CSS, and JavaScript live in the output file; the font stylesheet is loaded
from Google Fonts.

The same pipeline is available from Elixir:

```elixir
EasyBreezy.Export.html!(deck,
  theme: :nebula,
  size: {100, 30},
  output: "slides.html"
)
```

Capture and rendering are separate: `EasyBreezy.Export.capture/2` produces a
format-neutral `EasyBreezy.Export.Document`, and output formats implement the
`EasyBreezy.Export.Backend` behaviour.

## Full-image slides

Use the `:image` layout to fill the complete slide body with an image:

```elixir
%EasyBreezy.Slide{
  id: :missing_feature,
  title: "The missing feature",
  layout: :image,
  payload: %{
    path: Path.expand("typing-kitty.gif", __DIR__),
    alt: "The missing feature",
    width: 72,
    height: 36
  }
}
```

The equivalent Markdown slide is:

```markdown
---
layout: image
title: The missing feature
width: 72
height: 36
---
![Typing kitty](typing-kitty.gif)
```

Images use the Kitty graphics protocol, so a compatible terminal such as Kitty or Ghostty is
required. PNG and animated GIF sources are supported. GIF frames are decoded in Elixir, cached,
and sent as a terminal-driven animation in Kitty. Other compatible terminals, including Ghostty,
use timed frame retransmission because they do not currently implement Kitty's animation actions.
Explicit dimensions use terminal cells; images are scaled down proportionally when necessary and
centered in the available slide body.
