defmodule EasyBreezy.SlideTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.Slide

  defmodule ExampleView do
  end

  test "returns a static map payload" do
    payload = %{title: "Intro", items: ["One", "Two"]}

    assert Slide.resolve_payload(%Slide{layout: :bullets, payload: payload}, 80, 1) == payload
  end

  test "resolves a dynamic payload with the body width and step" do
    slide = %Slide{payload: fn body_width, step -> %{width: body_width, step: step} end}

    assert Slide.resolve_payload(slide, 72, 3) == %{width: 72, step: 3}
  end

  test "normalizes a Breeze view module payload" do
    slide = %Slide{layout: :breeze, payload: ExampleView}

    assert Slide.resolve_payload(slide, 80, 0) == %{view: ExampleView}
  end

  test "returns an empty payload for unsupported slide values" do
    assert Slide.resolve_payload(%Slide{payload: nil}, 80, 0) == %{}
    assert Slide.resolve_payload(nil, 80, 0) == %{}
  end
end
