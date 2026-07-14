defmodule EasyBreezy.PresenterView do
  @moduledoc false

  use Breeze.View

  alias EasyBreezy.Layouts.CodeSlide
  alias EasyBreezy.ElapsedTime
  alias EasyBreezy.LiveSlide
  alias EasyBreezy.PresenterScroll
  alias EasyBreezy.SourceEditor
  alias EasyBreezy.Slideshow.KittyImage
  alias Breeze.Theme

  import Breeze.Blocks
  import EasyBreezy.Layouts
  import EasyBreezy.Layouts.SourceEditorView

  @themes [:system16, :system, :nebula, :catppuccin, :dracula, :gruvbox, :nord, :solarized_light]
  @retry_ms 1_000
  @resubscribe_ms 50
  @clock_tick_ms 1_000
  @live_snapshot_tick_ms 100
  @live_slide_movement_keys [
    "ArrowUp",
    "ArrowDown",
    "ArrowLeft",
    "ArrowRight",
    "h",
    "j",
    "k",
    "l"
  ]

  def mount(opts, term) do
    deck = Keyword.fetch!(opts, :deck)
    sync_node = Keyword.get(opts, :presenter_sync_node) || Keyword.get(opts, :sync_node)
    sync_name = EasyBreezy.PresenterSync.name(opts)
    EasyBreezy.PresenterSync.connect(sync_node)

    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {theme_name, theme} = resolve_theme(Keyword.get(opts, :theme, :nebula))

    started_at_ms =
      Keyword.get_lazy(opts, :started_at_ms, fn -> System.monotonic_time(:millisecond) end)

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
        live_state: %{},
        live_snapshot: nil,
        live_snapshot_poll_ref: nil,
        presentation_monitor_ref: nil,
        presentation_pid: nil,
        sync_name: sync_name,
        sync_status: "connecting",
        themes: Keyword.get(opts, :themes, @themes),
        started_at_ms: started_at_ms,
        elapsed_label: ElapsedTime.label(started_at_ms),
        reset_timer_modal?: false,
        source_editor: nil,
        source_mode?: false,
        theme_name: theme_name,
        actual_theme_mode: term.theme.mode,
        theme_status: Theme.probe_status(term.theme) || :ready
      )
      |> assign_code_theme(theme_name)
      |> assign_theme_colors()
      |> put_local_keybindings(scroll_keybindings())
      |> subscribe_to_presentation()
      |> focus_current_live_slide()

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
    current_live_slide? = LiveSlide.live?(slide)
    current_live_snapshot? = live_snapshot_matches?(assigns.live_snapshot, slide)
    current_live_placeholder? = current_live_slide? and not current_live_snapshot?
    next_live_slide? = LiveSlide.live?(next_slide)
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
      |> assign(current_source?: assigns.source_mode?)
      |> assign(current_editing?: !is_nil(assigns.source_editor))
      |> assign(current_live_slide?: current_live_slide?)
      |> assign(current_live_snapshot?: current_live_snapshot?)
      |> assign(current_live_placeholder?: current_live_placeholder?)
      |> assign(next_live_slide?: next_live_slide?)
      |> assign(notes: notes)
      |> assign(
        render_context: %{
          theme_colors: assigns.theme_colors,
          code_theme: assigns.code_theme,
          animate_title_gradient?: false,
          image_scope: "presenter-current"
        },
        next_render_context: %{
          theme_colors: assigns.theme_colors,
          code_theme: assigns.code_theme,
          animate_title_gradient?: false,
          image_scope: "presenter-next"
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
            <box :if={@current_source? && @current_editing?} class="width-full height-full">
              <.source_editor_view
                title={"#{@slide.title} source"}
                editor={@source_editor}
                body_width={@current_body_width}
                body_height={@current_body_height}
                render_context={@render_context}
              />
            </box>
            <box :if={@current_source? && !@current_editing?} class="width-full height-full">
              <.slide_source
                slide={@slide}
                body_width={@current_body_width}
                body_height={@current_body_height}
                render_context={@render_context}
              />
            </box>
            <box :if={!@current_source? && !@current_live_slide?} class="width-full height-full">
              <.slide_body
                slide={@slide}
                step={@visible_step}
                body_width={@current_body_width}
                body_height={@current_body_height}
                live_state={@live_state}
                render_context={@render_context}
              />
            </box>
            <box
              :if={!@current_source? && @current_live_snapshot?}
              class="width-full height-full overflow-hidden"
            >
              {Map.get(@live_snapshot, :content, "")}
            </box>
            <box :if={!@current_source? && @current_live_placeholder?} class="width-full height-full">
              <box>{" "}</box>
              <box class="bold text-secondary">Live Slide</box>
              <box class="text-muted">{@slide.title}</box>
            </box>
          </box>
          <box style={@gutter_style}>{" "}</box>
          <box style={@next_style} class="border border-stroke bg-panel">
            <box
              :if={!is_nil(@next_slide) and !@next_live_slide?}
              style={@next_body_style}
              class="overflow-hidden"
            >
              <.slide_body
                slide={@next_slide}
                step={0}
                body_width={@next_body_width}
                body_height={@next_body_height}
                live_state={@live_state}
                render_context={@next_render_context}
              />
            </box>
            <box :if={@next_live_slide?} style={@next_body_style} class="overflow-hidden">
              <box>{" "}</box>
              <box class="bold text-secondary">Live Slide</box>
              <box class="text-muted">{@next_slide.title}</box>
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
      <.modal
        :if={@reset_timer_modal?}
        id="reset-timer-modal"
        width={44}
        height={7}
        dim
        br-change="close_reset_timer"
      >
        <:title>Reset Timer</:title>
        <box class="absolute left-2 top-2 text">Reset elapsed timer to 00:00?</box>
        <box class="absolute left-2 top-4 text-muted">Enter/y reset · Esc/n cancel</box>
      </.modal>
      <.flash_group flash={@breeze.flash} width={42}/>
    </box>
    """
  end

  def handle_event("close_reset_timer", _event, term) do
    {:noreply, close_reset_timer(term)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{reset_timer_modal?: true}} = term)
      when key in ["Enter", "y", "Y"] do
    {:noreply, reset_timer(term)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{reset_timer_modal?: true}} = term)
      when key in ["Escape", "n", "N"] do
    {:noreply, close_reset_timer(term)}
  end

  def handle_event(_, %{"key" => _key}, %{assigns: %{reset_timer_modal?: true}} = term) do
    {:noreply, term}
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => key}, term) when key in ["r", "R"] do
    {:noreply, open_reset_timer(term)}
  end

  def handle_event(
        _,
        %{"key" => _key} = event,
        %{assigns: %{source_editor: %SourceEditor{}}} = term
      ) do
    {:noreply, forward_input(term, event)}
  end

  def handle_event(_, %{"key" => "e"}, %{assigns: %{source_mode?: true}} = term) do
    {:noreply, send_command(term, :edit_source)}
  end

  def handle_event(_, %{"key" => key}, term) when key in @live_slide_movement_keys do
    cond do
      current_synced_live_slide?(term.assigns) ->
        {:noreply, forward_input(term, %{"key" => key})}

      key in ["ArrowRight", "l"] ->
        {:noreply, send_command(term, :next)}

      key in ["ArrowLeft", "h"] ->
        {:noreply, send_command(term, :previous)}

      true ->
        {:noreply, term}
    end
  end

  def handle_event(_, %{"key" => key}, term) when key in [" ", "PageDown"] do
    if current_synced_live_slide?(term.assigns) do
      {:noreply, forward_input(term, %{"key" => key})}
    else
      {:noreply, send_command(term, :next)}
    end
  end

  def handle_event(_, %{"key" => "PageUp"}, term) do
    if current_synced_live_slide?(term.assigns) do
      {:noreply, forward_input(term, %{"key" => "PageUp"})}
    else
      {:noreply, send_command(term, :previous)}
    end
  end

  def handle_event(_, %{"key" => "Home"}, term) do
    if current_synced_live_slide?(term.assigns) do
      {:noreply, forward_input(term, %{"key" => "Home"})}
    else
      {:noreply, send_command(term, :home)}
    end
  end

  def handle_event(_, %{"key" => "End"}, term) do
    if current_synced_live_slide?(term.assigns) do
      {:noreply, forward_input(term, %{"key" => "End"})}
    else
      {:noreply, send_command(term, :end)}
    end
  end

  def handle_event(_, %{"ctrlKey" => true, "key" => key}, term) when key in ["t", "T"] do
    {:noreply, send_command(term, :cycle_theme)}
  end

  def handle_event(_, %{"key" => "\x14"}, term), do: {:noreply, send_command(term, :cycle_theme)}

  def handle_event(_, %{"key" => "i"}, term),
    do: {:noreply, send_command(term, :toggle_source_mode)}

  def handle_event(_, %{"key" => "q"}, term) do
    {:stop, KittyImage.delete_overlay(term)}
  end

  def handle_event(_, %{"key" => _key} = event, term) do
    if current_synced_live_slide?(term.assigns) do
      {:noreply, forward_input(term, event)}
    else
      {:noreply, term}
    end
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {:noreply, assign(term, screen_width: screen_width, screen_height: screen_height)}
  end

  def handle_info(:presenter_sync_retry, term) do
    {:noreply, subscribe_to_presentation(term)}
  end

  def handle_info(
        {:DOWN, ref, :process, pid, _reason},
        %{assigns: %{presentation_monitor_ref: ref, presentation_pid: pid}} = term
      ) do
    Process.send_after(self(), :presenter_sync_retry, @resubscribe_ms)

    {:noreply,
     assign(term,
       presentation_monitor_ref: nil,
       presentation_pid: nil,
       sync_status: "connecting"
     )}
  end

  def handle_info(:clock_tick, term) do
    Process.send_after(self(), :clock_tick, @clock_tick_ms)
    {:noreply, assign(term, elapsed_label: ElapsedTime.label(term.assigns.started_at_ms))}
  end

  def handle_info(:live_snapshot_poll, term) do
    term = assign(term, live_snapshot_poll_ref: nil)

    if current_synced_live_slide?(term.assigns) do
      case EasyBreezy.PresenterSync.request_state(term.assigns.sync_name, self()) do
        :ok -> {:noreply, schedule_live_snapshot_poll(term), invalidate: false}
        :error -> {:noreply, term, invalidate: false}
      end
    else
      {:noreply, term, invalidate: false}
    end
  end

  def handle_info({:easy_breezy_presentation_state, payload}, term) when is_map(payload) do
    theme_name = Map.get(payload, :theme_name, term.assigns.theme_name)
    deck = Map.get(payload, :deck, term.assigns.deck)
    slide_index = Map.get(payload, :slide_index, term.assigns.slide_index)
    source_editor = Map.get(payload, :source_editor)

    source_saved? =
      source_saved?(term.assigns.deck, term.assigns.source_editor, deck, source_editor)

    live_snapshot = next_live_snapshot(term.assigns.live_snapshot, payload, deck, slide_index)
    started_at_ms = presentation_started_at_ms(payload, term.assigns.started_at_ms)

    previous_term = term

    term =
      term
      |> assign(
        deck: deck,
        slide_index: slide_index,
        step: Map.get(payload, :step, term.assigns.step),
        presentation_screen_width: Map.get(payload, :screen_width),
        presentation_screen_height: Map.get(payload, :screen_height),
        started_at_ms: started_at_ms,
        elapsed_label: ElapsedTime.label(started_at_ms),
        source_editor: source_editor,
        source_mode?: Map.get(payload, :source_mode?, term.assigns.source_mode?),
        theme_name: theme_name,
        actual_theme_mode: Map.get(payload, :actual_theme_mode, term.assigns.actual_theme_mode),
        theme_status: Map.get(payload, :theme_status, term.assigns.theme_status),
        live_snapshot: live_snapshot,
        sync_status: "connected"
      )
      |> assign_theme(theme_name)
      |> clamp_position()
      |> PresenterScroll.import(Map.get(payload, :scroll_state))
      |> focus_current_live_slide()
      |> maybe_delete_presenter_image_overlay(previous_term)
      |> schedule_live_snapshot_poll()
      |> maybe_put_source_saved_flash(source_saved?, deck)

    {:noreply, term}
  end

  def handle_info(_, term), do: {:noreply, term}

  defp subscribe_to_presentation(term) do
    case EasyBreezy.PresenterSync.subscribe(term.assigns.sync_name) do
      {:ok, pid} ->
        term
        |> monitor_presentation(pid)
        |> assign(sync_status: "connected")

      :error ->
        Process.send_after(self(), :presenter_sync_retry, @retry_ms)
        assign(term, sync_status: "connecting")
    end
  end

  defp monitor_presentation(
         %{assigns: %{presentation_pid: pid, presentation_monitor_ref: ref}} = term,
         pid
       )
       when is_pid(pid) and is_reference(ref),
       do: term

  defp monitor_presentation(term, pid) when is_pid(pid) do
    if is_reference(term.assigns.presentation_monitor_ref) do
      Process.demonitor(term.assigns.presentation_monitor_ref, [:flush])
    end

    assign(term,
      presentation_pid: pid,
      presentation_monitor_ref: Process.monitor(pid)
    )
  end

  defp send_command(term, command) do
    EasyBreezy.PresenterSync.command(term.assigns.sync_name, command)
    term
  end

  defp open_reset_timer(term), do: assign(term, reset_timer_modal?: true)

  defp close_reset_timer(term), do: assign(term, reset_timer_modal?: false)

  defp reset_timer(term) do
    started_at_ms = System.monotonic_time(:millisecond)

    term
    |> assign(
      reset_timer_modal?: false,
      started_at_ms: started_at_ms,
      elapsed_label: ElapsedTime.label(started_at_ms)
    )
    |> send_command(:reset_timer)
  end

  defp forward_input(term, event) do
    send_command(
      term,
      {:input, Map.take(event, ["key", "ctrlKey", "altKey", "shiftKey", "metaKey"])}
    )
  end

  defp scroll_keybindings do
    Enum.map(PresenterScroll.keys(), fn key ->
      {key, fn event, term -> {:noreply, sync_scroll(term, event)} end}
    end)
  end

  defp sync_scroll(term, event) do
    scroll_event = PresenterScroll.event(event)

    cond do
      match?(%SourceEditor{}, term.assigns.source_editor) ->
        forward_input(term, scroll_event)

      current_synced_live_slide?(term.assigns) ->
        forward_input(term, scroll_event)

      true ->
        term
        |> PresenterScroll.apply(scroll_event)
        |> send_command({:scroll, scroll_event})
    end
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

    term
    |> assign(slide_index: slide_index, step: step)
    |> focus_current_live_slide()
  end

  defp maybe_delete_presenter_image_overlay(term, previous_term) do
    previous_images = visible_image_keys(previous_term.assigns)
    current_images = visible_image_keys(term.assigns)

    if previous_images != current_images and (previous_images != [] or current_images != []) do
      KittyImage.delete_overlay(term)
    else
      term
    end
  end

  defp visible_image_keys(assigns) do
    {slide, slide_index, _step} = current_position(assigns)
    next_slide = Enum.at(assigns.deck.slides, slide_index + 1)
    current_slide = if assigns.source_mode?, do: nil, else: slide

    [{:current, current_slide}, {:next, next_slide}]
    |> Enum.flat_map(fn {slot, slide} ->
      slide
      |> image_slide_keys()
      |> Enum.map(fn key -> {slot, key} end)
    end)
  end

  defp image_slide_keys(nil), do: []

  defp image_slide_keys(%{layout: :image} = slide) do
    payload = resolve_slide_payload(slide, 80, 0)
    [{:full, Map.get(payload, :path) || Map.get(payload, :image_path)}]
  end

  defp image_slide_keys(slide) do
    slide
    |> resolve_slide_payload(80, 0)
    |> image_payload_keys()
  end

  defp image_payload_keys(payload) do
    []
    |> maybe_add_image_key(:left, Map.get(payload, :left_mode), Map.get(payload, :left_path))
    |> maybe_add_image_key(:right, Map.get(payload, :right_mode), Map.get(payload, :right_path))
  end

  defp maybe_add_image_key(keys, side, mode, path) when mode in [:image, "image"] do
    [{side, path} | keys]
  end

  defp maybe_add_image_key(keys, _side, _mode, _path), do: keys

  defp current_synced_live_slide?(assigns) do
    {slide, _slide_index, _step} = current_position(assigns)
    not assigns.source_mode? and LiveSlide.live?(slide) and LiveSlide.sync?(slide)
  end

  defp live_snapshot_matches?(snapshot, slide) when is_map(snapshot) do
    LiveSlide.live?(slide) and LiveSlide.sync?(slide) and
      Map.get(snapshot, :id) == LiveSlide.id(slide)
  end

  defp live_snapshot_matches?(_snapshot, _slide), do: false

  defp normalize_live_snapshot(%{id: id, content: content} = snapshot)
       when is_binary(id) and is_binary(content) do
    %{
      id: id,
      content: content,
      width: Map.get(snapshot, :width),
      height: Map.get(snapshot, :height)
    }
  end

  defp normalize_live_snapshot(%{"id" => id, "content" => content} = snapshot)
       when is_binary(id) and is_binary(content) do
    %{
      id: id,
      content: content,
      width: Map.get(snapshot, "width"),
      height: Map.get(snapshot, "height")
    }
  end

  defp normalize_live_snapshot(_snapshot), do: nil

  defp next_live_snapshot(previous_snapshot, payload, deck, slide_index) do
    snapshot = normalize_live_snapshot(Map.get(payload, :live_snapshot))
    slide = Enum.at(deck.slides, slide_index)

    cond do
      live_snapshot_matches?(snapshot, slide) ->
        snapshot

      live_snapshot_matches?(previous_snapshot, slide) ->
        previous_snapshot

      true ->
        nil
    end
  end

  defp schedule_live_snapshot_poll(%{assigns: %{live_snapshot_poll_ref: ref}} = term)
       when is_reference(ref),
       do: term

  defp schedule_live_snapshot_poll(term) do
    if current_synced_live_slide?(term.assigns) do
      ref = Process.send_after(self(), :live_snapshot_poll, @live_snapshot_tick_ms)
      assign(term, live_snapshot_poll_ref: ref)
    else
      term
    end
  end

  defp focus_current_live_slide(term) do
    {slide, _slide_index, _step} = current_position(term.assigns)

    if term.assigns.source_mode? do
      Breeze.View.focus(term, nil)
    else
      LiveSlide.focus(term, slide)
    end
  end

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

  defp presentation_started_at_ms(payload, fallback) do
    case Map.get(payload, :elapsed_ms) do
      elapsed_ms when is_integer(elapsed_ms) ->
        ElapsedTime.started_at_ms_from_elapsed(elapsed_ms)

      _elapsed_ms ->
        Map.get(payload, :started_at_ms, fallback)
    end
  end

  defp source_saved?(previous_deck, %SourceEditor{dirty?: true}, deck, source_editor) do
    Map.get(previous_deck, :source) != Map.get(deck, :source) and
      (is_nil(source_editor) or not source_editor.dirty?)
  end

  defp source_saved?(_previous_deck, _previous_editor, _deck, _source_editor), do: false

  defp maybe_put_source_saved_flash(term, true, %{source_path: path}) when is_binary(path),
    do: put_flash(term, :success, "Slide source written", id: "source-written", duration: 3_000)

  defp maybe_put_source_saved_flash(term, true, _deck),
    do: put_flash(term, :success, "Updated in memory", id: "source-written", duration: 3_000)

  defp maybe_put_source_saved_flash(term, false, _deck), do: term

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
