defmodule EasyBreezy.Navigation do
  @moduledoc false

  def next(deck, position) do
    {slide_index, step} = position = clamp(deck, position)
    slide = slide(deck, slide_index)

    cond do
      is_nil(slide) ->
        position

      step < slide_steps(slide) ->
        {slide_index, step + 1}

      slide_index < last_slide_index(deck) ->
        {slide_index + 1, 0}

      true ->
        position
    end
  end

  def previous(deck, position) do
    {slide_index, step} = position = clamp(deck, position)

    cond do
      step > 0 ->
        {slide_index, step - 1}

      slide_index > 0 ->
        previous_index = slide_index - 1
        {previous_index, slide_steps(slide(deck, previous_index))}

      true ->
        position
    end
  end

  def first(deck), do: clamp(deck, {0, 0})

  def last(%{slides: slides} = deck) when is_list(slides) and slides != [] do
    slide_index = length(slides) - 1
    clamp(deck, {slide_index, slide_steps(slide(deck, slide_index))})
  end

  def last(_deck), do: {0, 0}

  def clamp(%{slides: slides} = deck, {slide_index, step})
      when is_list(slides) and slides != [] do
    slide_index = slide_index |> integer_or_zero() |> max(0) |> min(length(slides) - 1)
    step = step |> integer_or_zero() |> max(0) |> min(slide_steps(slide(deck, slide_index)))

    {slide_index, step}
  end

  def clamp(_deck, _position), do: {0, 0}

  def slide(%{slides: slides}, slide_index)
      when is_list(slides) and is_integer(slide_index) and slide_index >= 0 do
    Enum.at(slides, slide_index)
  end

  def slide(_deck, _slide_index), do: nil

  defp last_slide_index(%{slides: slides}) when is_list(slides) and slides != [],
    do: length(slides) - 1

  defp last_slide_index(_deck), do: 0

  defp slide_steps(%{steps: steps}) when is_integer(steps) and steps >= 0, do: steps
  defp slide_steps(_slide), do: 0

  defp integer_or_zero(value) when is_integer(value), do: value
  defp integer_or_zero(_value), do: 0
end
