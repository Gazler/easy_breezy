defmodule EasyBreezy.NavigationTest do
  use ExUnit.Case, async: true

  alias EasyBreezy.{Deck, Navigation, Slide}

  setup do
    deck = %Deck{
      slides: [
        %Slide{id: :intro, steps: 0},
        %Slide{id: :details, steps: 2},
        %Slide{id: :outro, steps: 1}
      ]
    }

    %{deck: deck}
  end

  test "advances through steps before moving to the next slide", %{deck: deck} do
    assert Navigation.next(deck, {0, 0}) == {1, 0}
    assert Navigation.next(deck, {1, 0}) == {1, 1}
    assert Navigation.next(deck, {1, 1}) == {1, 2}
    assert Navigation.next(deck, {1, 2}) == {2, 0}
    assert Navigation.next(deck, {2, 0}) == {2, 1}
    assert Navigation.next(deck, {2, 1}) == {2, 1}
  end

  test "moves to the final step of the previous slide", %{deck: deck} do
    assert Navigation.previous(deck, {2, 1}) == {2, 0}
    assert Navigation.previous(deck, {2, 0}) == {1, 2}
    assert Navigation.previous(deck, {1, 2}) == {1, 1}
    assert Navigation.previous(deck, {1, 1}) == {1, 0}
    assert Navigation.previous(deck, {1, 0}) == {0, 0}
    assert Navigation.previous(deck, {0, 0}) == {0, 0}
  end

  test "returns the first and last logical positions", %{deck: deck} do
    assert Navigation.first(deck) == {0, 0}
    assert Navigation.last(deck) == {2, 1}
  end

  test "clamps slide and step bounds", %{deck: deck} do
    assert Navigation.clamp(deck, {-4, -2}) == {0, 0}
    assert Navigation.clamp(deck, {1, 99}) == {1, 2}
    assert Navigation.clamp(deck, {99, 99}) == {2, 1}
    assert Navigation.clamp(deck, {:invalid, nil}) == {0, 0}
  end

  test "handles an empty deck without inventing a slide" do
    deck = %Deck{slides: []}

    assert Navigation.first(deck) == {0, 0}
    assert Navigation.last(deck) == {0, 0}
    assert Navigation.next(deck, {0, 0}) == {0, 0}
    assert Navigation.previous(deck, {0, 0}) == {0, 0}
    assert Navigation.slide(deck, 0) == nil
  end
end
