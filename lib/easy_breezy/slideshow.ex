defmodule EasyBreezy.Slideshow do
  use Breeze.View

  alias EasyBreezy.Layouts.CodeSlide
  import EasyBreezy.Layouts
  import EasyBreezy.Transitions
  alias Breeze.Theme

  @themes [:system16, :system, :nebula, :catppuccin, :dracula, :gruvbox, :nord, :solarized_light]
  @title_gradient_tick_ms 90
  @title_gradient_phase_count 120

  def mount(opts, term) do
    deck = Keyword.fetch!(opts, :deck)

    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {theme_name, theme} = resolve_theme(Keyword.get(opts, :theme, :nebula))

    term =
      term
      |> maybe_enter_alt_screen(opts)
      |> put_theme(theme)

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
        themes: Keyword.get(opts, :themes, @themes),
        started_at_ms: System.monotonic_time(:millisecond),
        title_gradient_phase: 0,
        theme_name: theme_name,
        actual_theme_mode: term.theme.mode,
        theme_status: Theme.probe_status(term.theme) || :ready
      )
      |> assign_code_theme(theme_name)
      |> assign_theme_colors()
      |> assign_title_gradient(theme_name)

    maybe_schedule_title_gradient_tick(term)

    {:ok, clamp_position(term)}
  end

  def render(assigns) do
    {slide, slide_index, step} = visible_position(assigns)
    body_width = max(assigns.screen_width - 6, 20)
    body_height = max(assigns.screen_height - 6, 8)

    {title_gradient_start, title_gradient_end} = animated_title_gradient(assigns)

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
          title_gradient_start: title_gradient_start,
          title_gradient_end: title_gradient_end,
          code_theme: assigns.code_theme
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
    {:noreply, advance(term)}
  end

  def handle_event(_, %{"key" => key}, term) when key in ["ArrowLeft", "h", "PageUp"] do
    {:noreply, retreat(term)}
  end

  def handle_event(_, %{"key" => "Home"}, term) do
    previous_assigns = term.assigns

     {:noreply,
     term
     |> assign(slide_index: 0, step: 0)
     |> clamp_position()
     |> maybe_restart_title_gradient(previous_assigns)}
  end

  def handle_event(_, %{"key" => "End"}, term) do
    last_index = length(term.assigns.deck.slides) - 1
    last_slide = Enum.at(term.assigns.deck.slides, last_index)
    previous_assigns = term.assigns

     {:noreply,
     term
     |> assign(slide_index: last_index, step: last_slide.steps)
     |> clamp_position()
     |> maybe_restart_title_gradient(previous_assigns)}
  end

  def handle_event(_, %{"key" => "p"}, term) do
    {:noreply, assign(term, presenter?: not term.assigns.presenter?)}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => key}, term) when key in ["t", "T"] do
    {:noreply, cycle_theme(term)}
  end

  def handle_event(_, %{"key" => "\x14"}, term) do
    {:noreply, cycle_theme(term)}
  end

  def handle_event(_, %{"key" => key}, term) when key in ["q", "Escape"] do
    {:stop, maybe_cleanup_slide(term, current_slide(term.assigns))}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {:noreply, assign(term, screen_width: screen_width, screen_height: screen_height)}
  end

  def handle_info(:title_gradient_tick, term) do
    if title_gradient_active?(term.assigns) do
      schedule_title_gradient_tick()

      phase = rem((term.assigns.title_gradient_phase || 0) + 1, @title_gradient_phase_count)

      {:noreply, assign(term, title_gradient_phase: phase)}
    else
      {:noreply, term}
    end
  end

  def handle_info(:transition_tick, %{assigns: %{transition: nil}} = term), do: {:noreply, term}

  def handle_info(:transition_tick, term) do
    transition = term.assigns.transition
    frame = transition.frame + 1

    if frame >= transition.frames do
      previous_assigns = term.assigns

      {:noreply,
       term
       |> assign(
         slide_index: transition.to_index,
         step: transition.to_step,
         transition: nil
       )
       |> maybe_restart_title_gradient(previous_assigns)}
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
            term
            |> EasyBreezy.Transitions.start(next_index, 0, direction)
            |> maybe_restart_title_gradient(term.assigns)
          else
            term
            |> assign(slide_index: next_index, step: 0)
            |> maybe_cleanup_slide(slide)
            |> maybe_restart_title_gradient(term.assigns)
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
            term
            |> EasyBreezy.Transitions.start(previous_index, previous_slide.steps, direction)
            |> maybe_restart_title_gradient(term.assigns)
          else
            term
            |> assign(slide_index: previous_index, step: previous_slide.steps)
            |> maybe_cleanup_slide(slide)
            |> maybe_restart_title_gradient(term.assigns)
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
    |> maybe_cleanup_slide(previous_slide)
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

  defp assign_theme(term, theme_key) do
    {theme_name, theme} = resolve_theme(theme_key)
    term = put_theme(term, theme)

    assign(term,
      theme_name: theme_name,
      actual_theme_mode: term.theme.mode,
      theme_status: Theme.probe_status(term.theme) || :ready
    )
    |> assign_code_theme(theme_name)
    |> assign_theme_colors()
    |> assign_title_gradient(theme_name)
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

  defp assign_title_gradient(term, theme_name) do
    primary = Theme.color(term.theme, :primary)
    accent = Theme.color(term.theme, :accent)

    {start_color, end_color, accent_color} =
      if theme_name == :system16 do
        {primary, primary, primary}
      else
        secondary = Theme.color(term.theme, :secondary)
        {primary, secondary, accent || secondary}
      end

    assign(term,
      title_gradient_start: start_color,
      title_gradient_end: end_color,
      title_gradient_accent: accent_color
    )
  end

  defp animated_title_gradient(%{
         theme_name: :system16,
         title_gradient_start: start_color,
         title_gradient_end: end_color
       }),
       do: {start_color, end_color}

  defp animated_title_gradient(assigns) do
    start_color = assigns.title_gradient_start
    end_color = assigns.title_gradient_end
    accent_color = assigns.title_gradient_accent || end_color
    phase = (assigns.title_gradient_phase || 0) / @title_gradient_phase_count

    start_mix = wave(phase)
    end_mix = wave(phase + 0.33)

    {
      Theme.blend(start_color, accent_color, start_mix),
      Theme.blend(end_color, start_color, end_mix)
    }
  end

  defp wave(phase) do
    (:math.sin(phase * 2 * :math.pi()) + 1) / 2
  end

  defp maybe_schedule_title_gradient_tick(term) do
    if title_gradient_active?(term.assigns), do: schedule_title_gradient_tick()
    term
  end

  defp maybe_restart_title_gradient(term, previous_assigns) do
    if not title_gradient_active?(previous_assigns) and title_gradient_active?(term.assigns) do
      term
      |> assign(title_gradient_phase: 0)
      |> maybe_schedule_title_gradient_tick()
    else
      term
    end
  end

  defp title_gradient_active?(%{transition: %{from_index: from_index, to_index: to_index}, deck: %{slides: slides}}) do
    title_slide?(Enum.at(slides, from_index)) or title_slide?(Enum.at(slides, to_index))
  end

  defp title_gradient_active?(assigns) do
    title_slide?(current_slide(assigns))
  end

  defp title_slide?(%{layout: :title}), do: true
  defp title_slide?(_slide), do: false

  defp schedule_title_gradient_tick do
    Process.send_after(self(), :title_gradient_tick, @title_gradient_tick_ms)
  end

  defp resolve_theme(:system16), do: {:system16, :system16}
  defp resolve_theme(:system), do: {:system, :system}
  defp resolve_theme(:nebula), do: {:nebula, Theme.builtin(:nebula)}
  defp resolve_theme(:catppuccin), do: {:catppuccin, Theme.builtin(:catppuccin)}
  defp resolve_theme(:dracula), do: {:dracula, Theme.builtin(:dracula)}
  defp resolve_theme(:gruvbox), do: {:gruvbox, Theme.builtin(:gruvbox)}
  defp resolve_theme(:nord), do: {:nord, Theme.builtin(:nord)}
  defp resolve_theme(:solarized_light), do: {:solarized_light, Theme.builtin(:solarized, :light)}
  defp resolve_theme(_), do: resolve_theme(:nebula)

  defp cycle_theme(term) do
    current_theme = term.assigns.theme_name
    themes = term.assigns.themes || @themes

    next_theme =
      themes
      |> Enum.find_index(&(&1 == current_theme))
      |> case do
        nil -> hd(themes)
        index -> Enum.at(themes, rem(index + 1, length(themes)))
      end

    assign_theme(term, next_theme)
  end

  defp maybe_cleanup_slide(%{terminal: %{adapter: nil}} = term, _slide),
    do: term

  defp maybe_cleanup_slide(term, %{id: :image}) do
    maybe_write_cleanup_payload(term, EasyBreezy.Slideshow.KittyImage.delete_command())
  end

  defp maybe_cleanup_slide(term, %{payload: payload}) when is_map(payload) do
    case Map.get(payload, :cleanup_payload) do
      nil -> term
      cleanup_payload -> maybe_write_cleanup_payload(term, cleanup_payload)
    end
  end

  defp maybe_cleanup_slide(term, _slide), do: term

  defp maybe_write_cleanup_payload(term, cleanup_payload) when is_function(cleanup_payload, 0) do
    cleanup_payload
    |> then(& &1.())
    |> then(&maybe_write_cleanup_payload(term, &1))
  end

  defp maybe_write_cleanup_payload(term, cleanup_payload) when cleanup_payload in [nil, ""], do: term

  defp maybe_write_cleanup_payload(term, cleanup_payload) when is_binary(cleanup_payload) do
    %{term | terminal: Termite.Terminal.write(term.terminal, cleanup_payload)}
  rescue
    _ -> term
  end

  defp maybe_write_cleanup_payload(term, _cleanup_payload), do: term

end
