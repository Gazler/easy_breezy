defmodule EasyBreezy.Slideshow do
  use Breeze.View

  alias EasyBreezy.Layouts.CodeSlide
  import EasyBreezy.Layouts
  import EasyBreezy.Transitions
  alias Breeze.Theme

  @themes Theme.default_cycle()

  def mount(opts, term) do
    deck = Keyword.fetch!(opts, :deck)

    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)

    term =
      term
      |> maybe_enter_alt_screen(opts)
      |> Breeze.View.switch_theme(Keyword.get(opts, :theme, :nebula))

    term =
      term
      |> assign(
        deck: deck,
        slide_index: Keyword.get(opts, :slide_index, 0),
        step: Keyword.get(opts, :step, 0),
        transition: nil,
        screen_width: screen_width,
        screen_height: screen_height,
        presenter?: Keyword.get(opts, :presenter, false),
        presenter_mode: Keyword.get(opts, :presenter_mode, :single),
        presenter_sync_name: EasyBreezy.PresenterSync.name(opts),
        presenter_subscribers: MapSet.new(),
        themes: Keyword.get(opts, :themes, @themes),
        started_at_ms: System.monotonic_time(:millisecond)
      )
      |> assign_theme_context()
      |> maybe_register_presentation()
      |> maybe_publish_presentation_soon()

    {:ok, clamp_position(term)}
  end

  def render(assigns) do
    {slide, slide_index, step} = visible_position(assigns)
    body_width = max(assigns.screen_width - 6, 20)
    body_height = max(assigns.screen_height - 6, 8)

    assigns =
      assigns
      |> assign(slide: slide)
      |> assign(visible_slide_index: slide_index)
      |> assign(visible_step: step)
      |> assign(body_width: body_width)
      |> assign(body_height: body_height)
      |> assign(progress: progress(slide_index, assigns))
      |> assign(total_slides: length(assigns.deck.slides))
      |> assign(next_title: next_slide_title(assigns, slide_index))
      |> assign(
        render_context: %{
          theme_colors: assigns.theme_colors,
          code_theme: assigns.code_theme,
          animate_title_gradient?: true
        }
      )

    ~H"""
    <box class="width-screen height-screen bg text">
      <box class="grid grid-cols-1 grid-rows-3 width-screen height-screen">
        <box class="height-1 inline bg-panel text">
          <box class="bold text-primary"> {@deck.title} </box>
          <box class="text-muted"> {@screen_width}x{@screen_height} </box>
          <box class="text-muted"> {@theme_name}/{@actual_theme_mode} ({@theme_status}) </box>
          <box style="width-full" class="text-right">
            Slide {@visible_slide_index + 1}/{@total_slides} · Step {@visible_step + 1}/{@slide.steps + 1}
          </box>
        </box>
        <box class="height-full">
          <box class="border border-stroke bg-surface width-full height-full">
            <.slide_transition
              :if={@transition}
              transition={@transition}
              deck={@deck}
              body_width={@body_width}
              body_height={@body_height}
              render_context={@render_context}
            />
            <.slide_body
              :if={is_nil(@transition)}
              slide={@slide}
              step={@visible_step}
              body_width={@body_width}
              body_height={@body_height}
              render_context={@render_context}
            />
          </box>
        </box>
        <box :if={not @presenter?} class="height-1 inline bg-panel text">
          <box> ←/h prev </box>
          <box> →/l next </box>
          <box> space advance </box>
          <box class="text-muted"> ^t theme </box>
          <box style="width-full text-right"> q quit </box>
        </box>
        <box :if={@presenter?} class="height-1 inline bg-panel text">
          <box> Next: {@next_title} </box>
          <box class="text-muted"> ^t theme </box>
          <live
            id="presenter-clock"
            view={EasyBreezy.PresenterClock}
            class="width-full text-right bg-panel text"
            start_opts={[started_at_ms: @started_at_ms]}
          >
          </live>
        </box>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => key}, term) when key in [" ", "ArrowRight", "l", "PageDown"] do
    {:noreply, term |> advance() |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => key}, term) when key in ["ArrowLeft", "h", "PageUp"] do
    {:noreply, term |> retreat() |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => "Home"}, term) do
    {:noreply,
     term
     |> assign(slide_index: 0, step: 0)
     |> clamp_position()
     |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => "End"}, term) do
    last_index = length(term.assigns.deck.slides) - 1
    last_slide = Enum.at(term.assigns.deck.slides, last_index)

    {:noreply,
     term
     |> assign(slide_index: last_index, step: last_slide.steps)
     |> clamp_position()
     |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => "p"}, term) do
    {:noreply, assign(term, presenter?: not term.assigns.presenter?)}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => key}, term) when key in ["t", "T"] do
    {:noreply,
     term
     |> Breeze.View.cycle_theme(theme_cycle_opts(term))
     |> assign_theme_context()
     |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => "\x14"}, term) do
    {:noreply,
     term
     |> Breeze.View.cycle_theme(theme_cycle_opts(term))
     |> assign_theme_context()
     |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => key}, term) when key in ["q", "Escape"] do
    {:stop, term}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)

    {:noreply,
     term
     |> assign(screen_width: screen_width, screen_height: screen_height)
     |> maybe_publish_presentation_soon()}
  end

  def handle_info(:publish_presentation_state, term) do
    maybe_publish_presentation(term)
    {:noreply, term}
  end

  def handle_info({:easy_breezy_presenter_subscribe, pid}, term) when is_pid(pid) do
    Process.monitor(pid)

    term =
      update_in(term.assigns.presenter_subscribers, fn subscribers ->
        subscribers
        |> ensure_map_set()
        |> MapSet.put(pid)
      end)

    maybe_publish_presentation(term)
    {:noreply, term}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, term) when is_pid(pid) do
    {:noreply, remove_presenter_subscriber(term, pid)}
  end

  def handle_info({:easy_breezy_presenter_command, _pid, command}, term) do
    {:noreply, handle_presenter_command(command, term)}
  end

  def handle_info(:transition_tick, %{assigns: %{transition: nil}} = term), do: {:noreply, term}

  def handle_info(:transition_tick, term) do
    transition = term.assigns.transition
    frame = transition.frame + 1

    if frame >= transition.frames do
      {:noreply,
       term
       |> assign(
         slide_index: transition.to_index,
         step: transition.to_step,
         transition: nil
       )
       |> maybe_publish_presentation_soon()}
    else
      Process.send_after(self(), :transition_tick, transition.interval_ms)
      {:noreply, assign(term, transition: %{transition | frame: frame})}
    end
  end

  def handle_info(_, term), do: {:noreply, term}

  defp advance(term) do
    if term.assigns.transition do
      term
    else
      slide = current_slide(term.assigns)

      cond do
        term.assigns.step < slide.steps ->
          assign(term, step: term.assigns.step + 1)

        term.assigns.slide_index < length(term.assigns.deck.slides) - 1 ->
          next_index = term.assigns.slide_index + 1
          next_slide = Enum.at(term.assigns.deck.slides, next_index)
          direction = EasyBreezy.Transitions.direction(next_slide, :forward)

          if EasyBreezy.Transitions.enabled?(
               slide,
               next_slide,
               direction,
               term.assigns.actual_theme_mode
             ) do
            EasyBreezy.Transitions.start(term, next_index, 0, direction)
          else
            term
            |> assign(slide_index: next_index, step: 0)
            |> maybe_delete_image_overlay(slide)
          end

        true ->
          term
      end
    end
  end

  defp maybe_enter_alt_screen(term, opts) do
    if Keyword.get(opts, :alt_screen, true) and live_terminal?(term.terminal) do
      %{term | terminal: Termite.Screen.alt_screen(term.terminal)}
    else
      term
    end
  end

  defp live_terminal?(%Termite.Terminal{adapter: nil}), do: false
  defp live_terminal?(%Termite.Terminal{}), do: true
  defp live_terminal?(_terminal), do: false

  defp maybe_register_presentation(%{assigns: %{presenter_mode: :presentation}} = term) do
    EasyBreezy.PresenterSync.register(term.assigns.presenter_sync_name)
    term
  end

  defp maybe_register_presentation(term), do: term

  defp maybe_publish_presentation_soon(%{assigns: %{presenter_mode: :presentation}} = term) do
    send(self(), :publish_presentation_state)
    term
  end

  defp maybe_publish_presentation_soon(term), do: term

  defp maybe_publish_presentation(%{assigns: %{presenter_mode: :presentation}} = term) do
    EasyBreezy.PresenterSync.publish(
      ensure_map_set(term.assigns.presenter_subscribers),
      presentation_payload(term.assigns)
    )
  end

  defp maybe_publish_presentation(_term), do: :ok

  defp presentation_payload(assigns) do
    %{
      deck: assigns.deck,
      slide_index: assigns.slide_index,
      step: assigns.step,
      screen_width: assigns.screen_width,
      screen_height: assigns.screen_height,
      presenter?: assigns.presenter?,
      started_at_ms: assigns.started_at_ms,
      theme_name: assigns.theme_name,
      actual_theme_mode: assigns.actual_theme_mode,
      theme_status: assigns.theme_status
    }
  end

  defp remove_presenter_subscriber(term, pid) do
    update_in(term.assigns.presenter_subscribers, fn subscribers ->
      subscribers
      |> ensure_map_set()
      |> MapSet.delete(pid)
    end)
  end

  defp ensure_map_set(%MapSet{} = set), do: set
  defp ensure_map_set(_value), do: MapSet.new()

  defp handle_presenter_command(:next, term),
    do: term |> advance() |> maybe_publish_presentation_soon()

  defp handle_presenter_command(:previous, term),
    do: term |> retreat() |> maybe_publish_presentation_soon()

  defp handle_presenter_command(:home, term) do
    term
    |> assign(slide_index: 0, step: 0)
    |> clamp_position()
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command(:end, term) do
    last_index = length(term.assigns.deck.slides) - 1
    last_slide = Enum.at(term.assigns.deck.slides, last_index)

    term
    |> assign(slide_index: last_index, step: last_slide.steps)
    |> clamp_position()
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command(:cycle_theme, term) do
    term
    |> Breeze.View.cycle_theme(theme_cycle_opts(term))
    |> assign_theme_context()
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command(_command, term), do: term

  defp retreat(term) do
    if term.assigns.transition do
      term
    else
      cond do
        term.assigns.step > 0 ->
          assign(term, step: term.assigns.step - 1)

        term.assigns.slide_index > 0 ->
          previous_index = term.assigns.slide_index - 1
          previous_slide = Enum.at(term.assigns.deck.slides, previous_index)
          slide = current_slide(term.assigns)
          direction = EasyBreezy.Transitions.direction(slide, :backward)

          if EasyBreezy.Transitions.enabled?(
               slide,
               previous_slide,
               direction,
               term.assigns.actual_theme_mode
             ) do
            EasyBreezy.Transitions.start(term, previous_index, previous_slide.steps, direction)
          else
            term
            |> assign(slide_index: previous_index, step: previous_slide.steps)
            |> maybe_delete_image_overlay(slide)
          end

        true ->
          term
      end
    end
  end

  defp clamp_position(term) do
    deck = term.assigns.deck
    previous_slide = current_slide(term.assigns)
    slide_index = term.assigns.slide_index |> max(0) |> min(length(deck.slides) - 1)
    slide = Enum.at(deck.slides, slide_index)
    step = term.assigns.step |> max(0) |> min(slide.steps)

    term
    |> assign(slide_index: slide_index, step: step, transition: nil)
    |> maybe_delete_image_overlay(previous_slide)
  end

  defp visible_position(%{
         transition: %{to_index: slide_index, to_step: step},
         deck: %{slides: slides}
       }) do
    {Enum.at(slides, slide_index), slide_index, step}
  end

  defp visible_position(%{deck: %{slides: slides}, slide_index: slide_index, step: step}) do
    {Enum.at(slides, slide_index), slide_index, step}
  end

  defp current_slide(%{deck: %{slides: slides}, slide_index: slide_index}) do
    Enum.at(slides, slide_index)
  end

  defp next_slide_title(assigns, slide_index) do
    case Enum.at(assigns.deck.slides, slide_index + 1) do
      nil -> "end of deck"
      slide -> slide.title
    end
  end

  defp progress(slide_index, assigns) do
    total = max(length(assigns.deck.slides), 1)
    trunc((slide_index + 1) / total * 100)
  end

  defp assign_theme_context(term) do
    theme_name = current_breeze_theme_name(term) || Map.get(term.assigns, :theme_name) || :nebula

    assign(term,
      theme_name: theme_name,
      actual_theme_mode: current_breeze_theme_mode(term) || term.theme.mode,
      theme_status: current_breeze_theme_status(term) || Theme.probe_status(term.theme) || :ready
    )
    |> assign_code_theme(theme_name)
    |> assign_theme_colors()
  end

  defp assign_code_theme(term, theme_name) do
    assign(term, code_theme: CodeSlide.lumis_theme_name(theme_name))
  end

  defp assign_theme_colors(term) do
    assign(term,
      theme_colors: %{
        bg: Theme.color(term.theme, :bg),
        text: Theme.color(term.theme, :text),
        primary: Theme.color(term.theme, :primary),
        secondary: Theme.color(term.theme, :secondary),
        muted: Theme.color(term.theme, :muted),
        accent: Theme.color(term.theme, :accent),
        panel: Theme.color(term.theme, :panel),
        surface: Theme.color(term.theme, :surface),
        stroke: Theme.color(term.theme, :stroke)
      }
    )
  end

  defp current_breeze_theme_name(term) do
    get_in(term.assigns, [:breeze, :theme, :name])
  end

  defp current_breeze_theme_mode(term) do
    get_in(term.assigns, [:breeze, :theme, :actual_mode])
  end

  defp current_breeze_theme_status(term) do
    get_in(term.assigns, [:breeze, :theme, :status])
  end

  defp theme_cycle_opts(term) do
    [
      themes: term.assigns.themes || @themes,
      current: current_breeze_theme_name(term) || term.assigns.theme_name
    ]
  end

  defp maybe_delete_image_overlay(term, previous_slide) do
    if image_slide?(previous_slide) do
      EasyBreezy.Slideshow.KittyImage.delete_overlay(term)
    else
      term
    end
  end

  defp image_slide?(%{id: :image}), do: true
  defp image_slide?(%{payload: payload}), do: image_payload?(payload)
  defp image_slide?(_slide), do: false

  defp image_payload?(%{left_mode: mode}) when mode in [:image, "image"], do: true
  defp image_payload?(%{right_mode: mode}) when mode in [:image, "image"], do: true
  defp image_payload?(_payload), do: false
end
