defmodule EasyBreezy.PresenterView do
  @moduledoc false

  use Breeze.View

  alias EasyBreezy.Layouts.CodeSlide
  alias EasyBreezy.PresenterScroll
  alias EasyBreezy.Slideshow.KittyImage
  alias Breeze.Theme

  import EasyBreezy.Layouts

  @themes [:system16, :system, :nebula, :catppuccin, :dracula, :gruvbox, :nord, :solarized_light]
  @retry_ms 1_000
  @clock_tick_ms 1_000

  def mount(opts, term) do
    deck = Keyword.fetch!(opts, :deck)
    sync_node = Keyword.get(opts, :presenter_sync_node) || Keyword.get(opts, :sync_node)
    sync_name = EasyBreezy.PresenterSync.name(opts)
    EasyBreezy.PresenterSync.connect(sync_node)

    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {theme_name, theme} = resolve_theme(Keyword.get(opts, :theme, :nebula))

    term =
      term
      |> maybe_enter_alt_screen(opts)
      |> put_theme(theme)
      |> assign(
        deck: deck,
        slide_index: Keyword.get(opts, :slide_index, 0),
        step: Keyword.get(opts, :step, 0),
        screen_width: screen_width,
        screen_height: screen_height,
        presentation_screen_width: nil,
        presentation_screen_height: nil,
        sync_name: sync_name,
        sync_status: "connecting",
        themes: Keyword.get(opts, :themes, @themes),
        started_at_ms: System.monotonic_time(:millisecond),
        elapsed_label: elapsed_label(System.monotonic_time(:millisecond)),
        theme_name: theme_name,
        actual_theme_mode: term.theme.mode,
        theme_status: Theme.probe_status(term.theme) || :ready
      )
      |> assign_code_theme(theme_name)
      |> assign_theme_colors()
      |> put_local_keybindings(scroll_keybindings())
      |> subscribe_to_presentation()

    Process.send_after(self(), :clock_tick, @clock_tick_ms)

    {:ok, clamp_position(term)}
  end

  def render(assigns) do
    synced? =
      is_integer(assigns.presentation_screen_width) and
        is_integer(assigns.presentation_screen_height)

    {slide, slide_index, step} = current_position(assigns)
    next_slide = Enum.at(assigns.deck.slides, slide_index + 1)

    presentation_width = assigns.presentation_screen_width || 80
    presentation_height = assigns.presentation_screen_height || 24
    gutter_width = 1
    footer_height = 1
    preferred_notes_height = min(max(div(assigns.screen_height, 3), 5), 10)
    available_top_height = max(assigns.screen_height - preferred_notes_height - footer_height, 8)
    top_height = min(max(presentation_height - 2, 8), available_top_height)
    notes_height = max(assigns.screen_height - top_height - footer_height, 3)

    max_current_width = max(assigns.screen_width - gutter_width - 24, 20)
    current_width = min(presentation_width, max_current_width)

    next_width =
      min(presentation_width, max(assigns.screen_width - current_width - gutter_width, 20))

    presentation_body_width = max(presentation_width - 6, 20)
    presentation_body_height = max(min(presentation_height - 6, top_height - 4), 8)
    current_body_width = presentation_body_width
    current_body_height = presentation_body_height
    next_body_width = current_body_width
    next_body_height = current_body_height
    next_body_style = %{width: max(next_width - 2, 1), height: max(top_height - 2, 1)}
    next_label = next_label(next_slide, max(next_width - 2, 1))
    next_label_style = %{position: :absolute, left: 1, top: 0, width: String.length(next_label)}
    footer_clock_width = 18
    footer_left_width = min(34, max(div(assigns.screen_width, 3), 22))
    footer_middle_width = max(assigns.screen_width - footer_left_width - footer_clock_width, 1)
    notes = speaker_notes(slide, current_body_width, step)

    assigns =
      assigns
      |> assign(synced?: synced?)
      |> assign(slide: slide)
      |> assign(next_slide: next_slide)
      |> assign(visible_slide_index: slide_index)
      |> assign(visible_step: step)
      |> assign(total_slides: length(assigns.deck.slides))
      |> assign(current_style: %{width: current_width, height: top_height})
      |> assign(next_style: %{width: next_width, height: top_height})
      |> assign(notes_style: %{height: notes_height})
      |> assign(gutter_style: %{width: gutter_width, height: top_height})
      |> assign(footer_left_style: %{width: footer_left_width})
      |> assign(footer_middle_style: %{width: footer_middle_width})
      |> assign(footer_clock_style: %{width: footer_clock_width})
      |> assign(current_body_width: current_body_width)
      |> assign(current_body_height: current_body_height)
      |> assign(next_body_width: next_body_width)
      |> assign(next_body_height: next_body_height)
      |> assign(next_body_style: next_body_style)
      |> assign(next_label: next_label)
      |> assign(next_label_style: next_label_style)
      |> assign(notes: notes)
      |> assign(
        render_context: %{
          theme_colors: assigns.theme_colors,
          code_theme: assigns.code_theme,
          animate_title_gradient?: false
        }
      )

    ~H"""
    <box class="width-screen height-screen bg text">
      <box :if={!@synced?} class="width-full height-full border border-stroke bg-surface">
        <box class="bold text-primary">Presenter</box>
        <box class="text-muted">Waiting for presentation node...</box>
        <box class="text-muted">
          Run the audience view as slides@host with presenter_mode: :presentation.
        </box>
      </box>
      <box :if={@synced?} class="width-full height-full">
        <box class="inline width-full">
          <box style={@current_style} class="border border-stroke bg-surface overflow-hidden">
            <.slide_body
              slide={@slide}
              step={@visible_step}
              body_width={@current_body_width}
              body_height={@current_body_height}
              render_context={@render_context}
            />
          </box>
          <box style={@gutter_style}>
          </box>
          <box style={@next_style} class="border border-stroke bg-panel">
            <box :if={!is_nil(@next_slide)} style={@next_body_style} class="overflow-hidden">
              <.slide_body
                slide={@next_slide}
                step={0}
                body_width={@next_body_width}
                body_height={@next_body_height}
                render_context={@render_context}
              />
            </box>
            <box
              :if={@next_label != ""}
              style={@next_label_style}
              class="bold text-secondary bg-panel"
            >
              {@next_label}
            </box>
          </box>
        </box>
        <box style={@notes_style} class="border border-stroke bg-surface overflow-hidden">
          <box class="bold text-secondary">Speaker notes</box>
          <box :if={@notes == []} class="text-muted">No notes for this slide.</box>
          <box :for={line <- @notes}>{line}</box>
        </box>
        <box class="height-1 inline bg-panel text">
          <box style={@footer_left_style}>
            Slide {@visible_slide_index + 1}/{@total_slides} · Step {@visible_step + 1}/{@slide.steps + 1}
          </box>
          <box style={@footer_middle_style} class="text-muted">
            presentation {@presentation_screen_width}x{@presentation_screen_height}
          </box>
          <box class="text-right bg-panel text" style={@footer_clock_style}>{@elapsed_label}</box>
        </box>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => key}, term) when key in [" ", "ArrowRight", "l", "PageDown"] do
    {:noreply, send_command(term, :next)}
  end

  def handle_event(_, %{"key" => key}, term) when key in ["ArrowLeft", "h", "PageUp"] do
    {:noreply, send_command(term, :previous)}
  end

  def handle_event(_, %{"key" => "Home"}, term), do: {:noreply, send_command(term, :home)}
  def handle_event(_, %{"key" => "End"}, term), do: {:noreply, send_command(term, :end)}

  def handle_event(_, %{"ctrlKey" => true, "key" => key}, term) when key in ["t", "T"] do
    {:noreply, send_command(term, :cycle_theme)}
  end

  def handle_event(_, %{"key" => "\x14"}, term), do: {:noreply, send_command(term, :cycle_theme)}

  def handle_event(_, %{"key" => key}, term) when key in ["q", "Escape"] do
    {:stop, KittyImage.delete_overlay(term)}
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {:noreply, assign(term, screen_width: screen_width, screen_height: screen_height)}
  end

  def handle_info(:presenter_sync_retry, term) do
    {:noreply, subscribe_to_presentation(term)}
  end

  def handle_info(:clock_tick, term) do
    Process.send_after(self(), :clock_tick, @clock_tick_ms)
    {:noreply, assign(term, elapsed_label: elapsed_label(term.assigns.started_at_ms))}
  end

  def handle_info({:easy_breezy_presentation_state, payload}, term) when is_map(payload) do
    theme_name = Map.get(payload, :theme_name, term.assigns.theme_name)

    previous_term = term

    term =
      term
      |> assign(
        deck: Map.get(payload, :deck, term.assigns.deck),
        slide_index: Map.get(payload, :slide_index, term.assigns.slide_index),
        step: Map.get(payload, :step, term.assigns.step),
        presentation_screen_width: Map.get(payload, :screen_width),
        presentation_screen_height: Map.get(payload, :screen_height),
        started_at_ms: Map.get(payload, :started_at_ms, term.assigns.started_at_ms),
        elapsed_label:
          elapsed_label(Map.get(payload, :started_at_ms, term.assigns.started_at_ms)),
        theme_name: theme_name,
        actual_theme_mode: Map.get(payload, :actual_theme_mode, term.assigns.actual_theme_mode),
        theme_status: Map.get(payload, :theme_status, term.assigns.theme_status),
        sync_status: "connected"
      )
      |> assign_theme(theme_name)
      |> clamp_position()
      |> PresenterScroll.import(Map.get(payload, :scroll_state))
      |> maybe_delete_presenter_image_overlay(previous_term)

    {:noreply, term}
  end

  def handle_info(_, term), do: {:noreply, term}

  defp subscribe_to_presentation(term) do
    case EasyBreezy.PresenterSync.subscribe(term.assigns.sync_name) do
      {:ok, _pid} ->
        assign(term, sync_status: "connected")

      :error ->
        Process.send_after(self(), :presenter_sync_retry, @retry_ms)
        assign(term, sync_status: "connecting")
    end
  end

  defp send_command(term, command) do
    EasyBreezy.PresenterSync.command(term.assigns.sync_name, command)
    term
  end

  defp scroll_keybindings do
    Enum.map(PresenterScroll.keys(), fn key ->
      {key, fn event, term -> {:noreply, sync_scroll(term, event)} end}
    end)
  end

  defp sync_scroll(term, event) do
    scroll_event = PresenterScroll.event(event)

    term
    |> PresenterScroll.apply(scroll_event)
    |> send_command({:scroll, scroll_event})
  end

  defp current_position(%{deck: %{slides: slides}, slide_index: slide_index, step: step}) do
    slide = Enum.at(slides, slide_index) || List.first(slides)
    {slide, slide_index, step}
  end

  defp clamp_position(term) do
    deck = term.assigns.deck
    slide_index = term.assigns.slide_index |> max(0) |> min(length(deck.slides) - 1)
    slide = Enum.at(deck.slides, slide_index)
    step = term.assigns.step |> max(0) |> min(slide.steps)
    assign(term, slide_index: slide_index, step: step)
  end

  defp maybe_delete_presenter_image_overlay(term, previous_term) do
    if visible_image_slide?(previous_term.assigns) do
      KittyImage.delete_overlay(term)
    else
      term
    end
  end

  defp visible_image_slide?(assigns) do
    {slide, slide_index, _step} = current_position(assigns)
    next_slide = Enum.at(assigns.deck.slides, slide_index + 1)

    image_slide?(slide) or image_slide?(next_slide)
  end

  defp image_slide?(nil), do: false
  defp image_slide?(%{id: :image}), do: true

  defp image_slide?(slide) do
    slide
    |> resolve_slide_payload(80, 0)
    |> image_payload?()
  end

  defp image_payload?(%{right_mode: :image}), do: true
  defp image_payload?(%{right_mode: "image"}), do: true
  defp image_payload?(%{left_mode: :image}), do: true
  defp image_payload?(%{left_mode: "image"}), do: true
  defp image_payload?(_payload), do: false

  defp speaker_notes(slide, body_width, step) do
    payload = resolve_slide_payload(slide, body_width, step)

    payload
    |> Map.get(:notes)
    |> normalize_notes()
  end

  defp normalize_notes(nil), do: []

  defp normalize_notes(notes) when is_binary(notes) do
    String.split(notes, "\n", trim: true)
  end

  defp normalize_notes(notes) when is_list(notes) do
    Enum.map(notes, &to_string/1)
  end

  defp normalize_notes(note), do: [to_string(note)]

  defp elapsed_label(started_at_ms) do
    total_seconds = div(System.monotonic_time(:millisecond) - started_at_ms, 1_000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "Elapsed #{pad2(minutes)}:#{pad2(seconds)}"
  end

  defp pad2(int) when int < 10, do: "0#{int}"
  defp pad2(int), do: Integer.to_string(int)

  defp resolve_slide_payload(%{payload: payload}, body_width, step) when is_function(payload, 2),
    do: payload.(body_width, step)

  defp resolve_slide_payload(%{payload: payload}, _body_width, _step) when is_map(payload),
    do: payload

  defp resolve_slide_payload(_slide, _body_width, _step), do: %{}

  defp next_label(nil, width), do: truncate_label("Next: End of deck", width)
  defp next_label(slide, width), do: truncate_label("Next: #{slide.title}", width)

  defp truncate_label(_label, width) when width <= 0, do: ""

  defp truncate_label(label, width) do
    if String.length(label) <= width do
      label
    else
      label
      |> String.slice(0, max(width - 3, 0))
      |> Kernel.<>("...")
      |> String.slice(0, width)
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
end
