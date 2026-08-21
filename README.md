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

## Presenter mode

Start EPMD, then run the audience and presenter views in separate terminals:

```console
cd examples
epmd -daemon
mix easy_breezy.slides markdown_slides.exs
mix easy_breezy.presenter markdown_slides.exs
```

Both tasks require a script path (or other `mix run` execution arguments). The
tasks use the long node names
`slides@127.0.0.1` and `presenter@127.0.0.1`; they report an error instead of
starting EPMD automatically when it is unavailable.

### Timing runs

In the presenter view, press `Ctrl+r` and confirm the timer reset to start a
timing run. EasyBreezy records a wall-clock enter and leave time for each
forward slide visit. Pausing the presentation timer does not pause slide
timing. Backward navigation is treated as an ignored detour: it creates no
visits and its duration is excluded until the presentation catches up to its
previous furthest slide.

The footer shows the current slide duration. The newest completed run is used
as the expected per-slide timing automatically; press `r` to browse and select
another run, or `c` in the run picker to clear the overlay. Resetting again or
quitting the presenter with `q` completes the active run.

Runs are written incrementally as human-readable JSON beneath
`.easy_breezy/timings/` in the directory from which the presentation was
launched. An initial file is saved on reset, then updated atomically after each
forward slide change and when the run completes. Pass `metadata_dir:` to
`EasyBreezy.run/1` to use a different metadata directory.

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
