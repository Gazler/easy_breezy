Code.require_file("counter.ex", __DIR__)

EasyBreezy.run(
  deck: Path.expand("markdown_slides.md", __DIR__),
  themes: [:system16, :system, :nebula, :catppuccin, :dracula, :gruvbox, :nord, :solarized_light]
)
