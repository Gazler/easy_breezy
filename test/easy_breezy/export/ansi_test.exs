defmodule EasyBreezy.Export.ANSITest do
  use ExUnit.Case, async: true

  alias BackBreeze.Box
  alias EasyBreezy.Export.{ANSI, Frame}

  test "resolves ANSI colours and attributes into positioned runs" do
    content =
      "plain " <>
        "\e[1;4;38;2;12;34;56;48;5;17mstyled" <>
        "\e[0m <tag>\nend\e[3m界"

    frame = ANSI.parse(%Box{content: content}, width: 40, height: 2)

    assert Frame.plain_text(frame) == "plain styled <tag>\nend界"
    assert frame.background == {0, 0, 95}

    styled = Enum.find(frame.runs, &(&1.text == "styled"))

    assert styled.x == 6
    assert styled.y == 0
    assert styled.width == 6
    assert styled.style.bold
    assert styled.style.underline
    assert styled.style.foreground == {12, 34, 56}
    assert styled.style.background == {0, 0, 95}

    wide = Enum.find(frame.runs, &(&1.text == "界"))
    assert %{x: 3, y: 1, width: 2, style: %{italic: true}} = wide
  end
end
