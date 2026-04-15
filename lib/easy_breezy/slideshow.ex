defmodule EasyBreezy.Slideshow do
  use Breeze.View

  alias EasyBreezy.Layouts.CodeSlide
  import EasyBreezy.Layouts
  import EasyBreezy.Transitions
  alias Breeze.Theme

  @themes [:system16, :system, :nebula, :catppuccin, :dracula, :gruvbox, :nord, :solarized_light]

  def mount(opts, term) do
    deck = Keyword.fetch!(opts, :deck)

    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {theme_name, theme} = resolve_theme(Keyword.get(opts, :theme, :nebula))

    term = put_theme(term, theme)

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
        theme_name: theme_name,
        actual_theme_mode: term.theme.mode,
        theme_status: Theme.probe_status(term.theme) || :ready
      )
      |> assign_code_theme(theme_name)
      |> assign_theme_colors()
      |> assign_title_gradient(theme_name)

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
          title_gradient_start: assigns.title_gradient_start,
          title_gradient_end: assigns.title_gradient_end,
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
    {:noreply, clamp_position(assign(term, slide_index: 0, step: 0))}
  end

  def handle_event(_, %{"key" => "End"}, term) do
    last_index = length(term.assigns.deck.slides) - 1
    last_slide = Enum.at(term.assigns.deck.slides, last_index)
    {:noreply, clamp_position(assign(term, slide_index: last_index, step: last_slide.steps))}
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
    {:stop, term}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {:noreply, assign(term, screen_width: screen_width, screen_height: screen_height)}
  end

  def handle_info(:transition_tick, %{assigns: %{transition: nil}} = term), do: {:noreply, term}

  def handle_info(:transition_tick, term) do
    transition = term.assigns.transition
    frame = transition.frame + 1

    if frame >= transition.frames do
      {:noreply,
       assign(term,
         slide_index: transition.to_index,
         step: transition.to_step,
         transition: nil
       )}
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
            |> maybe_delete_image_overlay(slide.id)
          end

        true ->
          term
      end
    end
  end

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
            |> maybe_delete_image_overlay(slide.id)
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
    |> maybe_delete_image_overlay(previous_slide.id)
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

    {start_color, end_color} =
      if theme_name == :system16 do
        {primary, primary}
      else
        {primary, Theme.color(term.theme, :secondary)}
      end

    assign(term, title_gradient_start: start_color, title_gradient_end: end_color)
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

  defp maybe_delete_image_overlay(%{terminal: %{adapter: nil}} = term, _previous_slide_id),
    do: term

  defp maybe_delete_image_overlay(term, :image) do
    %{
      term
      | terminal:
          Termite.Terminal.write(term.terminal, EasyBreezy.Slideshow.KittyImage.delete_command())
    }
  rescue
    _ -> term
  end

  defp maybe_delete_image_overlay(term, _previous_slide_id), do: term
end
