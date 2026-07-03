defmodule EasyBreezy.FigletTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Figlet

  test "renders the built-in future font" do
    assert Figlet.render("FIGLET FONTS", :future) ==
             """
             ┏━╸╻┏━╸╻  ┏━╸╺┳╸   ┏━╸┏━┓┏┓╻╺┳╸┏━┓
             ┣╸ ┃┃╺┓┃  ┣╸  ┃    ┣╸ ┃ ┃┃┗┫ ┃ ┗━┓
             ╹  ╹┗━┛┗━╸┗━╸ ╹    ╹  ┗━┛╹ ╹ ╹ ┗━┛
             """
             |> String.trim_trailing()
  end

  test "renders ANSI Shadow from the bundled FLF font" do
    lines =
      "BR"
      |> Figlet.render(:ansi_shadow, trim_vertical: true)
      |> String.split("\n")

    assert lines == [
             "██████╗ ██████╗ ",
             "██╔══██╗██╔══██╗",
             "██████╔╝██████╔╝",
             "██╔══██╗██╔══██╗",
             "██████╔╝██║  ██║",
             "╚═════╝ ╚═╝  ╚═╝"
           ]
  end

  test "loads built-in fonts by string name" do
    assert Figlet.render("FIGLET", "future") == Figlet.render("FIGLET", :future)
  end

  test "renders the built-in Doom font" do
    rendered = Figlet.render("DOOM", :doom, trim_vertical: true)

    assert rendered =~ "|  \\/  |"
    assert rendered =~ "| .  . |"
  end

  test "renders the built-in JS Stick Letters font" do
    assert "FUN"
           |> Figlet.render(:js_stick_letters, trim_vertical: true)
           |> trim_trailing_lines() ==
             """
              ___
             |__  |  | |\\ |
             |    \\__/ | \\|
             """
             |> String.trim_trailing()
  end

  test "loads a font from a file path" do
    path =
      Path.join(System.tmp_dir!(), "easy_breezy_figlet_#{System.unique_integer([:positive])}.flf")

    File.write!(path, one_line_font(%{" " => "$", "A" => "alpha", "B" => "beta"}))
    on_exit(fn -> File.rm(path) end)

    assert Figlet.render("A B", path) == "alpha beta"
  end

  defp one_line_font(overrides) do
    glyphs =
      32..126
      |> Enum.map(fn codepoint ->
        grapheme = <<codepoint::utf8>>
        glyph = Map.get(overrides, grapheme, grapheme)
        glyph <> "@"
      end)
      |> Enum.join("\n")

    "flf2a$ 1 1 1 0 0\n" <> glyphs <> "\n"
  end

  defp trim_trailing_lines(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
  end
end
