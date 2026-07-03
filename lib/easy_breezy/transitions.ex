defmodule EasyBreezy.Transitions do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Layouts

  @slide_transition_duration_ms 200
  @reference_horizontal_distance 80
  @reference_vertical_distance 24
  @transition_columns_per_frame 10
  @transition_min_frames 4

  attr(:transition, :map, required: true)
  attr(:deck, :map, required: true)
  attr(:body_width, :integer, required: true)
  attr(:body_height, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def slide_transition(assigns) do
    from_slide = Enum.at(assigns.deck.slides, assigns.transition.from_index)
    to_slide = Enum.at(assigns.deck.slides, assigns.transition.to_index)

    assigns =
      assigns
      |> assign(from_slide: from_slide)
      |> assign(to_slide: to_slide)

    distance =
      div(assigns.transition.frame * assigns.transition.distance, assigns.transition.frames)

    {from_left, from_top, to_left, to_top} =
      transition_positions(
        assigns.transition.direction,
        assigns.body_width,
        assigns.body_height,
        distance
      )

    assigns =
      assigns
      |> assign(from_left: from_left)
      |> assign(from_top: from_top)
      |> assign(to_left: to_left)
      |> assign(to_top: to_top)
      |> assign(
        transition_render_context:
          transition_render_context(assigns.render_context, assigns.transition)
      )

    ~H"""
    <box class="width-full height-full overflow-hidden">
      <box
        style={%{position: :absolute, left: @from_left, top: @from_top}}
        class="width-full height-full"
      >
        <.slide_body
          slide={@from_slide}
          step={@transition.from_step}
          body_width={@body_width}
          body_height={@body_height}
          render_context={@transition_render_context}
        />
      </box>
      <box
        style={%{position: :absolute, left: @to_left, top: @to_top}}
        class="width-full height-full"
      >
        <.slide_body
          slide={@to_slide}
          step={@transition.to_step}
          body_width={@body_width}
          body_height={@body_height}
          render_context={@transition_render_context}
        />
      </box>
    </box>
    """
  end

  def start(term, to_index, to_step, direction) do
    body_width = max(term.assigns.screen_width - 6, 20)
    body_height = max(term.assigns.screen_height - 6, 8)
    distance = transition_distance(direction, body_width, body_height)
    frames = transition_frame_count(direction, distance)
    interval_ms = transition_interval_ms(direction, distance, frames)
    frozen_now = System.monotonic_time(:millisecond)

    Process.send_after(self(), :transition_tick, interval_ms)

    Breeze.View.assign(term,
      transition: %{
        from_index: term.assigns.slide_index,
        from_step: term.assigns.step,
        to_index: to_index,
        to_step: to_step,
        direction: direction,
        distance: distance,
        frame: 0,
        frames: frames,
        interval_ms: interval_ms,
        animation_frozen_now: frozen_now
      }
    )
  end

  def direction(slide, :forward), do: incoming_transition_direction(slide.transition)
  def direction(slide, :backward), do: reverse_transition_direction(slide.transition)

  def enabled?(%{disable_transitions?: true}, _next_slide, _direction, _theme_mode), do: false
  def enabled?(_slide, %{disable_transitions?: true}, _direction, _theme_mode), do: false
  def enabled?(_slide, _next_slide, _direction, _theme_mode), do: true

  def transition_frames(body_width) when is_integer(body_width) do
    max(div(body_width, @transition_columns_per_frame), @transition_min_frames)
  end

  def transition_interval_ms(direction, distance, frames)
      when is_integer(distance) and is_integer(frames) and frames > 0 do
    duration_ms = scaled_transition_duration_ms(direction, distance)
    max(div(duration_ms, frames), 1)
  end

  defp transition_frame_count(_direction, distance), do: transition_frames(distance)

  defp scaled_transition_duration_ms(direction, distance)
       when direction in [:forward, :backward] do
    scale_duration(distance, @reference_horizontal_distance)
  end

  defp scaled_transition_duration_ms(direction, distance) when direction in [:up, :down] do
    scale_duration(distance, @reference_vertical_distance)
  end

  defp scale_duration(distance, reference_distance) do
    distance = max(distance, 1)

    scale =
      max(reference_distance / distance, 1.0)

    round(@slide_transition_duration_ms * scale)
  end

  defp incoming_transition_direction(:slide), do: :forward
  defp incoming_transition_direction(:slide_up), do: :down

  defp reverse_transition_direction(:slide), do: :backward
  defp reverse_transition_direction(:slide_up), do: :up

  defp transition_distance(direction, body_width, _body_height)
       when direction in [:forward, :backward],
       do: body_width

  defp transition_distance(direction, _body_width, body_height) when direction in [:up, :down],
    do: body_height

  defp transition_render_context(render_context, transition) when is_map(render_context) do
    render_context
    |> Map.put(:animate_title_gradient?, true)
    |> Map.put(:animation_frozen_now, Map.get(transition, :animation_frozen_now))
  end

  defp transition_render_context(_render_context, transition) do
    %{
      animate_title_gradient?: true,
      animation_frozen_now: Map.get(transition, :animation_frozen_now)
    }
  end

  defp transition_positions(:forward, body_width, _body_height, distance),
    do: {-distance, 0, body_width - distance, 0}

  defp transition_positions(:backward, body_width, _body_height, distance),
    do: {distance, 0, distance - body_width, 0}

  defp transition_positions(:down, _body_width, body_height, distance),
    do: {0, -distance, 0, body_height - distance}

  defp transition_positions(:up, _body_width, body_height, distance),
    do: {0, distance, 0, distance - body_height}
end
