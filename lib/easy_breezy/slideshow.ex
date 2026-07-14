defmodule EasyBreezy.Slideshow do
  use Breeze.View

  alias EasyBreezy.Layouts.CodeSlide
  alias EasyBreezy.Deck.Markdown.Editor, as: MarkdownEditor
  alias EasyBreezy.ElapsedTime
  alias EasyBreezy.LiveSlide
  alias EasyBreezy.PresenterScroll
  alias EasyBreezy.SourceEditor
  import Breeze.Blocks
  import EasyBreezy.Layouts
  import EasyBreezy.Layouts.SourceEditorView
  import EasyBreezy.Transitions
  alias Breeze.Theme

  @themes Theme.default_cycle()
  @live_snapshot_timeout_ms 1_000
  @live_snapshot_refresh_ms 100
  @presenter_session_retry_ms 50
  # Breeze's direct server input path leaves CSI-u Escape as "27u".
  @escape_keys ["Escape", "Esc", "\e", "27u"]
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
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    body_width = max(screen_width - 6, 20)
    deck = opts |> Keyword.fetch!(:deck) |> normalize_deck_steps(body_width)

    started_at_ms =
      Keyword.get_lazy(opts, :started_at_ms, fn -> System.monotonic_time(:millisecond) end)

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
        presenter_session_pid: nil,
        presenter_session_monitor_ref: nil,
        presenter_session_retry_ref: nil,
        presenter_session_retry_token: nil,
        presenter_subscriber_count: 0,
        presentation_revision: 0,
        presentation_publish_revision: 0,
        presentation_broadcast_revision: -1,
        publish_pending?: false,
        live_snapshot_request: nil,
        deferred_snapshot_publish?: false,
        live_snapshot_refresh_ref: nil,
        live_snapshot_refresh_token: nil,
        keybindings_bar?: Keyword.get(opts, :keybindings_bar?, false),
        theme_status?: Keyword.get(opts, :theme_status?, false),
        source_editor: Keyword.get(opts, :source_editor),
        source_mode?: Keyword.get(opts, :source_mode?, false),
        live_state: %{},
        themes: Keyword.get(opts, :themes, @themes),
        started_at_ms: started_at_ms,
        goto_modal?: false,
        goto_slide_input: "",
        goto_slide_error: nil
      )
      |> assign_theme_context()
      |> maybe_put_scroll_keybindings()
      |> maybe_start_presentation_session()
      |> maybe_restore_source_save_flash(opts)

    {:ok, term |> clamp_position() |> focus_visible_live_slide()}
  end

  def render(assigns) do
    {slide, slide_index, step} = visible_position(assigns)
    footer? = footer_visible?(assigns)
    body_width = max(assigns.screen_width - 6, 20)
    body_height = max(assigns.screen_height - if(footer?, do: 6, else: 5), 8)

    assigns =
      assigns
      |> assign(slide: slide)
      |> assign(visible_slide_index: slide_index)
      |> assign(visible_step: step)
      |> assign(footer?: footer?)
      |> assign(root_grid_class: root_grid_class(footer?))
      |> assign(body_width: body_width)
      |> assign(body_height: body_height)
      |> assign(progress: progress(slide_index, assigns))
      |> assign(total_slides: length(assigns.deck.slides))
      |> assign(next_title: next_slide_title(assigns, slide_index))
      |> assign(
        render_context: %{
          theme_colors: assigns.theme_colors,
          code_theme: assigns.code_theme,
          animate_title_gradient?: true,
          image_scope: "presentation"
        }
      )
      |> maybe_publish_after_render()

    ~H"""
    <box class="width-screen height-screen bg text">
      <box class={@root_grid_class}>
        <box class="height-1 inline bg-panel text">
          <box class="bold text-primary"> {@deck.title} </box>
          <box class="text-muted"> {@screen_width}x{@screen_height} </box>
          <box :if={@theme_status?} class="text-muted">
            {@theme_name}/{@actual_theme_mode} ({@theme_status})
          </box>
          <box style="width-full" class="text-right">
            Slide {@visible_slide_index + 1}/{@total_slides} · Step {@visible_step + 1}/{@slide.steps + 1}
          </box>
        </box>
        <box class="height-full">
          <box class="border border-stroke bg-surface width-full height-full">
            <.slide_transition
              :if={@transition && !@source_mode?}
              transition={@transition}
              deck={@deck}
              body_width={@body_width}
              body_height={@body_height}
              live_state={@live_state}
              render_context={@render_context}
            />
            <.slide_body
              :if={is_nil(@transition) && !@source_mode?}
              slide={@slide}
              step={@visible_step}
              body_width={@body_width}
              body_height={@body_height}
              live_state={@live_state}
              render_context={@render_context}
            />
            <.slide_source
              :if={@source_mode? && is_nil(@source_editor)}
              slide={@slide}
              body_width={@body_width}
              body_height={@body_height}
              render_context={@render_context}
            />
            <.source_editor_view
              :if={@source_mode? && !is_nil(@source_editor)}
              title={"#{@slide.title} source"}
              editor={@source_editor}
              body_width={@body_width}
              body_height={@body_height}
              render_context={@render_context}
            />
          </box>
        </box>
        <box :if={not @presenter? && @keybindings_bar?} class="height-1 inline bg-panel text">
          <box> ←/h prev </box>
          <box> →/l next </box>
          <box> space advance </box>
          <box> g go to </box>
          <box class="text-muted"> ^t theme </box>
          <box class="text-muted"> T theme info </box>
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
      <.modal
        :if={@goto_modal?}
        id="goto-slide-modal"
        width={36}
        height={8}
        dim
        br-change="close_goto_slide"
      >
        <:title>Go To Slide</:title>
        <box class="absolute left-2 top-2 text-muted">Slide 1-{@total_slides}</box>
        <.input
          id="goto-slide-input"
          input-value={@goto_slide_input}
          input-placeholder="Enter slide"
          br-change="goto_slide_changed"
          default-focus
          class="absolute left-2 top-3 width-32"
        >
          {@goto_slide_input}
        </.input>
        <box :if={@goto_slide_error} class="absolute left-2 top-5 text-error">
          {@goto_slide_error}
        </box>
      </.modal>
      <.flash_group flash={@breeze.flash} width={42}/>
    </box>
    """
  end

  def handle_event("close_goto_slide", _event, term) do
    {:noreply, close_goto_slide(term)}
  end

  def handle_event("goto_slide_changed", %{value: value}, term) do
    {:noreply, assign(term, goto_slide_input: slide_number_input(value), goto_slide_error: nil)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{goto_modal?: true}} = term)
      when key in ["Enter", "\r"] do
    {:noreply, submit_goto_slide(term)}
  end

  def handle_event(_, %{"key" => key}, %{assigns: %{goto_modal?: true}} = term)
      when key in @escape_keys do
    {:noreply, close_goto_slide(term)}
  end

  def handle_event(_, %{"key" => _key}, %{assigns: %{goto_modal?: true}} = term) do
    {:noreply, term}
  end

  def handle_event(
        _,
        %{"key" => _key} = event,
        %{assigns: %{source_editor: %SourceEditor{}}} = term
      ) do
    {:noreply, handle_source_editor_event(term, event)}
  end

  def handle_event(_, %{"key" => "e"}, %{assigns: %{source_mode?: true}} = term) do
    {:noreply, term |> open_source_editor() |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => "g"}, term) do
    {:noreply, open_goto_slide(term)}
  end

  def handle_event(_, %{"key" => "?"}, term) do
    {:noreply, assign(term, keybindings_bar?: not term.assigns.keybindings_bar?)}
  end

  def handle_event(_, %{"key" => "T"}, term) do
    {:noreply, assign(term, theme_status?: not term.assigns.theme_status?)}
  end

  def handle_event(_, %{"key" => "i"}, term) do
    {:noreply, term |> toggle_source_mode() |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => key}, term) when key in @live_slide_movement_keys do
    cond do
      key in ["ArrowRight", "l"] ->
        {:noreply, term |> advance() |> maybe_publish_presentation_soon()}

      key in ["ArrowLeft", "h"] ->
        {:noreply, term |> retreat() |> maybe_publish_presentation_soon()}

      visible_synced_live_slide?(term.assigns) ->
        {:noreply, focus_visible_live_slide(term)}

      true ->
        {:noreply, term}
    end
  end

  def handle_event(_, %{"key" => key}, term) when key in [" ", "PageDown"] do
    {:noreply, term |> advance() |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => "PageUp"}, term) do
    {:noreply, term |> retreat() |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => "Home"}, term) do
    {:noreply,
     term
     |> jump_to_position(0, 0)
     |> focus_visible_live_slide()
     |> maybe_publish_presentation_soon()}
  end

  def handle_event(_, %{"key" => "End"}, term) do
    last_index = length(term.assigns.deck.slides) - 1
    last_slide = Enum.at(term.assigns.deck.slides, last_index)

    {:noreply,
     term
     |> jump_to_position(last_index, last_slide.steps)
     |> focus_visible_live_slide()
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

  def handle_event(_, %{"key" => "q"}, term) do
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

  def handle_info({:publish_presentation_state, _queued_revision}, term) do
    term =
      term
      |> assign(publish_pending?: false)
      |> maybe_publish_presentation()

    {:noreply, term, invalidate: false}
  end

  def handle_info({:clear_source_save_notice, id}, term) do
    term =
      case Map.get(term.assigns, :source_save_notice) do
        %{id: ^id} -> assign(term, source_save_notice: nil)
        _notice -> term
      end

    {:noreply, term, invalidate: false}
  end

  def handle_info(
        {:presenter_session_retry, token},
        %{assigns: %{presenter_session_retry_token: token}} = term
      ) do
    term = assign(term, presenter_session_retry_ref: nil, presenter_session_retry_token: nil)
    {:noreply, maybe_start_presentation_session(term), invalidate: false}
  end

  def handle_info({:presenter_session_retry, _stale_token}, term),
    do: {:noreply, term, invalidate: false}

  def handle_info(
        {:easy_breezy_presenter_subscribers, session, count},
        %{assigns: %{presenter_session_pid: session}} = term
      )
      when is_integer(count) and count >= 0 do
    term = assign(term, presenter_subscriber_count: count)

    term =
      if count > 0 do
        maybe_publish_presentation_soon(term)
      else
        cancel_live_snapshot_refresh(term)
      end

    {:noreply, term, invalidate: false}
  end

  def handle_info(
        {:easy_breezy_presenter_state_request, session, _subscriber},
        %{assigns: %{presenter_session_pid: session}} = term
      ) do
    {:noreply, maybe_publish_presentation_soon(term), invalidate: false}
  end

  def handle_info(
        {:easy_breezy_presenter_command, session, _subscriber, command},
        %{assigns: %{presenter_session_pid: session}} = term
      ) do
    {:noreply, handle_presenter_command(command, term)}
  end

  def handle_info({:breeze_live_snapshot, ref, id, {:ok, snapshot}}, term)
      when is_binary(id) and is_map(snapshot) do
    {:noreply, finish_live_snapshot_request(term, ref, id, snapshot), invalidate: false}
  end

  def handle_info({:breeze_live_snapshot, ref, id, _reply}, term) do
    {:noreply, finish_live_snapshot_request(term, ref, id, nil), invalidate: false}
  end

  def handle_info({:live_snapshot_timeout, ref}, term) do
    {:noreply, timeout_live_snapshot_request(term, ref), invalidate: false}
  end

  def handle_info(
        {:DOWN, ref, :process, session, _reason},
        %{
          assigns: %{
            presenter_session_pid: session,
            presenter_session_monitor_ref: ref
          }
        } = term
      ) do
    term =
      term
      |> cancel_live_snapshot_refresh()
      |> cancel_live_snapshot_request()
      |> assign(
        presenter_session_pid: nil,
        presenter_session_monitor_ref: nil,
        presenter_subscriber_count: 0
      )
      |> schedule_presenter_session_retry()

    {:noreply, term, invalidate: false}
  end

  def handle_info(
        {:presentation_live_snapshot_refresh, token},
        %{assigns: %{live_snapshot_refresh_token: token}} = term
      ) do
    term =
      term
      |> assign(live_snapshot_refresh_ref: nil, live_snapshot_refresh_token: nil)
      |> maybe_publish_presentation_soon()

    {:noreply, term, invalidate: false}
  end

  def handle_info({:presentation_live_snapshot_refresh, _stale_token}, term),
    do: {:noreply, term, invalidate: false}

  def handle_info(
        {:transition_tick, id},
        %{assigns: %{transition: %{id: id} = transition}} = term
      ) do
    frame = transition.frame + 1

    if frame >= transition.frames do
      {:noreply,
       term
       |> assign(
         slide_index: transition.to_index,
         step: transition.to_step,
         transition: nil
       )
       |> focus_visible_live_slide()
       |> maybe_publish_presentation_soon()}
    else
      timer_ref = Process.send_after(self(), {:transition_tick, id}, transition.interval_ms)

      {:noreply, assign(term, transition: %{transition | frame: frame, timer_ref: timer_ref})}
    end
  end

  def handle_info({:transition_tick, _stale_id}, term), do: {:noreply, term, invalidate: false}

  def handle_info(_, term), do: {:noreply, term}

  defp footer_visible?(%{presenter?: true}), do: true
  defp footer_visible?(%{keybindings_bar?: keybindings_bar?}), do: keybindings_bar?

  defp root_grid_class(true),
    do: "grid grid-cols-1 grid-rows-3 width-screen height-screen"

  defp root_grid_class(false),
    do: "grid grid-cols-1 grid-rows-2 width-screen height-screen"

  defp open_goto_slide(term) do
    term
    |> assign(goto_modal?: true, goto_slide_input: "", goto_slide_error: nil)
    |> Breeze.View.focus("goto-slide-input")
  end

  defp close_goto_slide(term) do
    assign(term, goto_modal?: false, goto_slide_input: "", goto_slide_error: nil)
  end

  defp submit_goto_slide(term) do
    total_slides = length(term.assigns.deck.slides)

    case parse_goto_slide(term.assigns.goto_slide_input, total_slides) do
      {:ok, slide_index} ->
        term
        |> assign(
          goto_modal?: false,
          goto_slide_input: "",
          goto_slide_error: nil
        )
        |> jump_to_slide(slide_index)
        |> maybe_publish_presentation_soon()

      {:error, message} ->
        term
        |> assign(goto_slide_error: message)
        |> Breeze.View.focus("goto-slide-input")
    end
  end

  defp parse_goto_slide(input, total_slides) do
    case Integer.parse(String.trim(input)) do
      {slide_number, ""} when slide_number >= 1 and slide_number <= total_slides ->
        {:ok, slide_number - 1}

      _other ->
        {:error, "Enter 1-#{total_slides}"}
    end
  end

  defp slide_number_input(value) do
    String.replace(value || "", ~r/\D/, "")
  end

  defp advance(term) do
    term =
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

    focus_visible_live_slide(term)
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

  defp normalize_deck_steps(%{slides: slides} = deck, body_width) do
    %{deck | slides: Enum.map(slides, &normalize_slide_steps(&1, body_width))}
  end

  defp normalize_slide_steps(
         %EasyBreezy.Slide{layout: :code, payload: payload} = slide,
         body_width
       ) do
    payload
    |> resolve_code_payload_for_steps(body_width)
    |> Map.get(:code_focus_ranges, [])
    |> CodeSlide.step_count()
    |> case do
      nil -> slide
      steps -> %{slide | steps: steps}
    end
  end

  defp normalize_slide_steps(slide, _body_width), do: slide

  defp resolve_code_payload_for_steps(payload, body_width) when is_function(payload, 2) do
    payload.(body_width, 0)
  end

  defp resolve_code_payload_for_steps(payload, _body_width), do: payload

  defp maybe_start_presentation_session(
         %{assigns: %{presenter_mode: :presentation, presenter_session_pid: pid}} = term
       )
       when is_pid(pid),
       do: term

  defp maybe_start_presentation_session(%{assigns: %{presenter_mode: :presentation}} = term) do
    case EasyBreezy.PresenterSync.ensure_presentation(
           term.assigns.presenter_sync_name,
           self()
         ) do
      {:ok, session} ->
        monitor_ref = Process.monitor(session)

        term
        |> cancel_presenter_session_retry()
        |> assign(
          presenter_session_pid: session,
          presenter_session_monitor_ref: monitor_ref
        )
        |> maybe_publish_presentation_soon()

      {:error, _reason} ->
        schedule_presenter_session_retry(term)
    end
  end

  defp maybe_start_presentation_session(term), do: term

  defp schedule_presenter_session_retry(%{assigns: %{presenter_session_retry_ref: ref}} = term)
       when is_reference(ref),
       do: term

  defp schedule_presenter_session_retry(term) do
    token = make_ref()

    timer_ref =
      Process.send_after(
        self(),
        {:presenter_session_retry, token},
        @presenter_session_retry_ms
      )

    assign(term,
      presenter_session_retry_ref: timer_ref,
      presenter_session_retry_token: token
    )
  end

  defp cancel_presenter_session_retry(term) do
    cancel_timer(term.assigns.presenter_session_retry_ref)
    assign(term, presenter_session_retry_ref: nil, presenter_session_retry_token: nil)
  end

  defp maybe_put_scroll_keybindings(%{assigns: %{presenter_mode: :presentation}} = term) do
    put_local_keybindings(term, scroll_keybindings())
  end

  defp maybe_put_scroll_keybindings(term), do: term

  defp scroll_keybindings do
    Enum.map(PresenterScroll.keys(), fn key ->
      {key, fn event, term -> {:noreply, scroll_and_publish(term, event)} end}
    end)
  end

  defp scroll_and_publish(term, event) do
    cond do
      match?(%SourceEditor{}, term.assigns.source_editor) ->
        handle_source_editor_event(term, PresenterScroll.event(event))

      visible_synced_live_slide?(term.assigns) ->
        focus_visible_live_slide(term)

      true ->
        term
        |> PresenterScroll.apply(PresenterScroll.event(event))
        |> maybe_publish_presentation_soon()
    end
  end

  defp maybe_publish_presentation_soon(%{assigns: %{presenter_mode: :presentation}} = term) do
    revision = term.assigns.presentation_revision + 1
    term = assign(term, presentation_revision: revision)

    term =
      if is_pid(term.assigns.presenter_session_pid) and not term.assigns.publish_pending? do
        send(self(), {:publish_presentation_state, revision})
        assign(term, publish_pending?: true)
      else
        term
      end

    update_live_snapshot_refresh(term)
  end

  defp maybe_publish_presentation_soon(term), do: term

  defp maybe_publish_presentation(
         %{assigns: %{presenter_mode: :presentation, presenter_session_pid: session}} = term
       )
       when is_pid(session) do
    case request_server_live_snapshot(term) do
      {:requested, term} -> term
      {:not_requested, term} -> publish_presentation(term, presentation_live_snapshot(term))
    end
  end

  defp maybe_publish_presentation(term), do: term

  defp publish_presentation(term, live_snapshot) do
    publish_revision = term.assigns.presentation_publish_revision + 1
    payload = presentation_payload(term, live_snapshot)

    case EasyBreezy.PresenterSync.publish(
           term.assigns.presenter_session_pid,
           publish_revision,
           payload
         ) do
      :ok ->
        assign(term,
          presentation_publish_revision: publish_revision,
          presentation_broadcast_revision: term.assigns.presentation_revision
        )

      :error ->
        term
    end
  end

  defp maybe_publish_after_render(%{presenter_mode: :presentation} = assigns) do
    if is_pid(assigns.presenter_session_pid) and not assigns.publish_pending? and
         assigns.presentation_broadcast_revision < assigns.presentation_revision do
      send(self(), {:publish_presentation_state, assigns.presentation_revision})
      Map.put(assigns, :publish_pending?, true)
    else
      assigns
    end
  end

  defp maybe_publish_after_render(assigns), do: assigns

  defp presentation_payload(term, live_snapshot) do
    assigns = term.assigns
    {_slide, slide_index, step} = visible_position(assigns)

    %{
      deck: assigns.deck,
      slide_index: slide_index,
      step: step,
      screen_width: assigns.screen_width,
      screen_height: assigns.screen_height,
      presenter?: assigns.presenter?,
      started_at_ms: assigns.started_at_ms,
      elapsed_ms: ElapsedTime.elapsed_ms(assigns.started_at_ms),
      source_mode?: assigns.source_mode?,
      source_editor: SourceEditor.snapshot(assigns.source_editor),
      theme_name: assigns.theme_name,
      actual_theme_mode: assigns.actual_theme_mode,
      theme_status: assigns.theme_status,
      live_snapshot: live_snapshot,
      scroll_state: PresenterScroll.export(term)
    }
  end

  defp update_live_snapshot_refresh(term) do
    cond do
      term.assigns.presenter_subscriber_count == 0 ->
        cancel_live_snapshot_refresh(term)

      not is_pid(term.assigns.presenter_session_pid) ->
        cancel_live_snapshot_refresh(term)

      not is_binary(visible_live_slide_id(term.assigns)) ->
        cancel_live_snapshot_refresh(term)

      is_reference(term.assigns.live_snapshot_refresh_ref) ->
        term

      true ->
        token = make_ref()

        timer_ref =
          Process.send_after(
            self(),
            {:presentation_live_snapshot_refresh, token},
            @live_snapshot_refresh_ms
          )

        assign(term,
          live_snapshot_refresh_ref: timer_ref,
          live_snapshot_refresh_token: token
        )
    end
  end

  defp cancel_live_snapshot_refresh(term) do
    cancel_timer(term.assigns.live_snapshot_refresh_ref)
    assign(term, live_snapshot_refresh_ref: nil, live_snapshot_refresh_token: nil)
  end

  defp handle_presenter_command(:next, term),
    do: term |> advance() |> maybe_publish_presentation_soon()

  defp handle_presenter_command(:previous, term),
    do: term |> retreat() |> maybe_publish_presentation_soon()

  defp handle_presenter_command(:home, term) do
    term
    |> jump_to_position(0, 0)
    |> focus_visible_live_slide()
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command(:end, term) do
    last_index = length(term.assigns.deck.slides) - 1
    last_slide = Enum.at(term.assigns.deck.slides, last_index)

    term
    |> jump_to_position(last_index, last_slide.steps)
    |> focus_visible_live_slide()
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command(:cycle_theme, term) do
    term
    |> Breeze.View.cycle_theme(theme_cycle_opts(term))
    |> assign_theme_context()
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command(:reset_timer, term) do
    term
    |> assign(started_at_ms: System.monotonic_time(:millisecond))
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command(:toggle_source_mode, term) do
    term
    |> toggle_source_mode()
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command(:edit_source, term) do
    term
    |> open_source_editor()
    |> maybe_publish_presentation_soon()
  end

  defp handle_presenter_command({:scroll, event}, term) when is_map(event) do
    if visible_synced_live_slide?(term.assigns) do
      focus_visible_live_slide(term)
    else
      term
      |> PresenterScroll.apply(event)
      |> maybe_publish_presentation_soon()
    end
  end

  defp handle_presenter_command({:input, %{"key" => _key} = event}, term) do
    if match?(%SourceEditor{}, term.assigns.source_editor) do
      handle_source_editor_event(term, event)
    else
      case dispatch_visible_live_input(term, event) do
        {:consumed, term} -> maybe_publish_presentation_soon(term)
        {:not_consumed, term} -> handle_presenter_key_event(event, term)
      end
    end
  end

  defp handle_presenter_command(_command, term), do: term

  defp handle_presenter_key_event(%{"key" => key}, term)
       when key in ["ArrowRight", "l", " ", "PageDown"],
       do: handle_presenter_command(:next, term)

  defp handle_presenter_key_event(%{"key" => key}, term) when key in ["ArrowLeft", "h", "PageUp"],
    do: handle_presenter_command(:previous, term)

  defp handle_presenter_key_event(%{"key" => "Home"}, term),
    do: handle_presenter_command(:home, term)

  defp handle_presenter_key_event(%{"key" => "End"}, term),
    do: handle_presenter_command(:end, term)

  defp handle_presenter_key_event(_event, term), do: term

  defp dispatch_visible_live_input(term, event) do
    slide = visible_slide(term.assigns)

    with false <- term.assigns.source_mode?,
         true <- LiveSlide.live?(slide) and LiveSlide.sync?(slide),
         id when is_binary(id) <- LiveSlide.id(slide) do
      case dispatch_server_live_input(term, id, event) do
        {:ok, result} -> result
        :error -> dispatch_child_live_input(term, id, event)
      end
    else
      _other -> {:not_consumed, term}
    end
  end

  defp dispatch_server_live_input(%{server: server} = term, id, event)
       when is_pid(server) and is_binary(id) do
    if function_exported?(Breeze.Server, :dispatch_live_input, 4) do
      case apply(Breeze.Server, :dispatch_live_input, [server, id, event, []]) do
        {:noreply, focused, true} ->
          {:ok, {:consumed, %{term | focused: focused}}}

        {:noreply, focused, false} ->
          {:ok, {:not_consumed, %{term | focused: focused}}}

        {:stop, focused, true} ->
          {:ok, {:consumed, %{term | focused: focused}}}

        {:stop, focused, false} ->
          {:ok, {:not_consumed, %{term | focused: focused}}}

        _other ->
          :error
      end
    else
      :error
    end
  catch
    :exit, _reason -> :error
  end

  defp dispatch_server_live_input(_term, _id, _event), do: :error

  defp dispatch_child_live_input(term, id, event) do
    with %{pid: pid} when is_pid(pid) <- Map.get(term.children, id),
         true <- Process.alive?(pid) do
      case Breeze.ChildServer.dispatch_input(pid, event) do
        {:noreply, focused, true} ->
          {:consumed, %{term | focused: live_focus(id, focused)}}

        {:noreply, focused, false} ->
          {:not_consumed, %{term | focused: live_focus(id, focused)}}

        {:stop, focused, true} ->
          {:consumed, %{term | focused: live_focus(id, focused)}}

        {:stop, focused, false} ->
          {:not_consumed, %{term | focused: live_focus(id, focused)}}
      end
    else
      _other -> {:not_consumed, term}
    end
  end

  defp live_focus(id, focused) when is_binary(focused), do: id <> "::" <> focused
  defp live_focus(id, _focused), do: id

  defp retreat(term) do
    term =
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

    focus_visible_live_slide(term)
  end

  defp jump_to_slide(term, slide_index) do
    slide_index = clamp_slide_index(term.assigns.deck, slide_index)

    if is_nil(term.assigns.transition) and slide_index == term.assigns.slide_index do
      term
    else
      jump_to_position(term, slide_index, 0)
    end
  end

  defp jump_to_position(term, slide_index, step) do
    {slide_index, step} = clamped_position(term.assigns.deck, slide_index, step)

    if is_nil(term.assigns.transition) and slide_index == term.assigns.slide_index and
         step == term.assigns.step do
      term
    else
      do_jump_to_position(term, slide_index, step)
    end
  end

  defp do_jump_to_position(term, slide_index, step) do
    previous_slide = current_slide(term.assigns)

    term
    |> EasyBreezy.Transitions.cancel()
    |> assign(slide_index: slide_index, step: step)
    |> focus_visible_live_slide()
    |> maybe_delete_image_overlay(previous_slide)
  end

  defp clamp_position(term), do: clamp_position(term, current_slide(term.assigns))

  defp clamp_position(term, previous_slide) do
    deck = term.assigns.deck
    {slide_index, step} = clamped_position(deck, term.assigns.slide_index, term.assigns.step)

    term
    |> EasyBreezy.Transitions.cancel()
    |> assign(slide_index: slide_index, step: step)
    |> focus_visible_live_slide()
    |> maybe_delete_image_overlay(previous_slide)
  end

  defp clamped_position(deck, slide_index, step) do
    slide_index = clamp_slide_index(deck, slide_index)
    slide = Enum.at(deck.slides, slide_index)
    step = step |> max(0) |> min(slide.steps)

    {slide_index, step}
  end

  defp clamp_slide_index(deck, slide_index) do
    slide_index |> max(0) |> min(length(deck.slides) - 1)
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

  defp visible_slide(%{
         transition: %{to_index: slide_index},
         deck: %{slides: slides}
       }) do
    Enum.at(slides, slide_index)
  end

  defp visible_slide(assigns), do: current_slide(assigns)

  defp visible_synced_live_slide?(assigns) do
    if assigns.source_mode? do
      false
    else
      slide = visible_slide(assigns)
      LiveSlide.live?(slide) and LiveSlide.sync?(slide)
    end
  end

  defp visible_live_slide_id(assigns) do
    slide = visible_slide(assigns)

    if not assigns.source_mode? and LiveSlide.live?(slide) and LiveSlide.sync?(slide) do
      LiveSlide.id(slide)
    end
  end

  defp focus_visible_live_slide(%{assigns: %{source_mode?: true}} = term),
    do: Breeze.View.focus(term, nil)

  defp focus_visible_live_slide(term), do: LiveSlide.focus(term, visible_slide(term.assigns))

  defp toggle_source_mode(term) do
    source_mode? = not term.assigns.source_mode?

    term =
      term
      |> assign(source_mode?: source_mode?, source_editor: nil)
      |> focus_visible_live_slide()

    if source_mode? and image_slide?(visible_slide(term.assigns)) do
      EasyBreezy.Slideshow.KittyImage.delete_overlay(term)
    else
      term
    end
  end

  defp open_source_editor(term) do
    slide = visible_slide(term.assigns)

    case Map.get(slide, :source) do
      source when is_binary(source) -> assign(term, source_editor: SourceEditor.new(source))
      _source -> assign(term, source_editor: nil)
    end
  end

  defp handle_source_editor_event(term, event) do
    case SourceEditor.handle_key(term.assigns.source_editor, event) do
      {:ok, editor} ->
        term
        |> assign(source_editor: editor)
        |> maybe_publish_presentation_soon()

      {:command, command, editor} ->
        term
        |> assign(source_editor: editor)
        |> execute_source_editor_command(command)
        |> maybe_publish_presentation_soon()
    end
  end

  defp execute_source_editor_command(term, command) when command in ["w", "write"],
    do: save_source_editor(term, false)

  defp execute_source_editor_command(term, command) when command in ["wq", "x"],
    do: save_source_editor(term, true)

  defp execute_source_editor_command(term, "q") do
    if term.assigns.source_editor.dirty? do
      put_source_editor_message(term, "No write since last change (:q! to discard)")
    else
      close_source_editor(term)
    end
  end

  defp execute_source_editor_command(term, "q!"), do: close_source_editor(term)
  defp execute_source_editor_command(term, ""), do: term

  defp execute_source_editor_command(term, command),
    do: put_source_editor_message(term, "Not an editor command: #{command}")

  defp save_source_editor(term, close?) do
    editor = term.assigns.source_editor
    slide = visible_slide(term.assigns)

    with {:ok, deck, save_result} <-
           MarkdownEditor.save(term.assigns.deck, slide, SourceEditor.source(editor)) do
      body_width = max(term.assigns.screen_width - 6, 20)
      editor = SourceEditor.mark_saved(editor)

      term
      |> assign(
        deck: normalize_deck_steps(deck, body_width),
        source_editor: unless(close?, do: editor)
      )
      |> maybe_close_source_editor(close?)
      |> clamp_position()
      |> put_source_save_flash(save_result)
    else
      {:error, reason} -> put_source_editor_message(term, reason)
    end
  end

  defp save_message(:written), do: "Slide source written"
  defp save_message(:updated), do: "Updated in memory"

  defp put_source_save_flash(term, save_result) do
    notice = %{
      id: System.unique_integer([:positive, :monotonic]),
      message: save_message(save_result)
    }

    Process.send_after(self(), {:clear_source_save_notice, notice.id}, 3_000)

    term
    |> assign(source_save_notice: notice)
    |> put_flash(:success, notice.message, id: "source-written", duration: 3_000)
  end

  defp maybe_restore_source_save_flash(term, opts) do
    case Keyword.get(opts, :source_save_notice) do
      %{message: message} when is_binary(message) ->
        put_flash(term, :success, message, id: "source-written", duration: 3_000)

      _message ->
        term
    end
  end

  defp put_source_editor_message(term, message) do
    assign(term, source_editor: SourceEditor.put_message(term.assigns.source_editor, message))
  end

  defp maybe_close_source_editor(term, true), do: close_source_editor(term)
  defp maybe_close_source_editor(term, false), do: term

  defp close_source_editor(term) do
    term
    |> assign(source_editor: nil, source_mode?: false)
    |> focus_visible_live_slide()
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

  defp image_slide?(%{layout: :image}), do: true
  defp image_slide?(%{id: :image}), do: true
  defp image_slide?(%{payload: payload}), do: image_payload?(payload)
  defp image_slide?(_slide), do: false

  defp image_payload?(%{left_mode: mode}) when mode in [:image, "image"], do: true
  defp image_payload?(%{right_mode: mode}) when mode in [:image, "image"], do: true
  defp image_payload?(_payload), do: false

  defp presentation_live_snapshot(term) do
    with id when is_binary(id) <- visible_live_slide_id(term.assigns) do
      child_live_snapshot(term, id)
    else
      _other -> nil
    end
  end

  defp request_server_live_snapshot(%{server: server} = term)
       when is_pid(server) do
    with id when is_binary(id) <- visible_live_slide_id(term.assigns),
         true <- function_exported?(Breeze.Server, :request_live_snapshot, 5) do
      case term.assigns.live_snapshot_request do
        nil ->
          ref = make_ref()

          apply(Breeze.Server, :request_live_snapshot, [
            server,
            id,
            self(),
            ref,
            [compact_snapshot: true]
          ])

          timeout_ref =
            Process.send_after(self(), {:live_snapshot_timeout, ref}, @live_snapshot_timeout_ms)

          request = %{
            ref: ref,
            id: id,
            revision: term.assigns.presentation_revision,
            timeout_ref: timeout_ref
          }

          {:requested, assign(term, live_snapshot_request: request)}

        %{id: ^id, revision: revision}
        when revision == term.assigns.presentation_revision ->
          {:requested, term}

        _request ->
          {:requested, defer_snapshot_publish(term)}
      end
    else
      _other -> {:not_requested, term}
    end
  catch
    :exit, _reason -> {:not_requested, term}
  end

  defp request_server_live_snapshot(term), do: {:not_requested, term}

  defp finish_live_snapshot_request(term, ref, id, snapshot) do
    case term.assigns.live_snapshot_request do
      %{ref: ^ref} = request ->
        cancel_timer(request.timeout_ref)
        term = assign(term, live_snapshot_request: nil)

        term =
          if live_snapshot_request_current?(term, request, id) do
            publish_presentation(
              term,
              normalize_live_snapshot(snapshot, request.id)
            )
          else
            term
          end

        flush_deferred_snapshot_publish(term)

      _stale_request ->
        term
    end
  end

  defp timeout_live_snapshot_request(term, ref) do
    case term.assigns.live_snapshot_request do
      %{ref: ^ref} = request ->
        term = assign(term, live_snapshot_request: nil)

        term =
          if live_snapshot_request_current?(term, request, request.id) do
            publish_presentation(term, nil)
          else
            term
          end

        flush_deferred_snapshot_publish(term)

      _stale_request ->
        term
    end
  end

  defp live_snapshot_request_current?(term, request, reply_id) do
    request.id == reply_id and
      request.id == visible_live_slide_id(term.assigns) and
      request.revision == term.assigns.presentation_revision
  end

  defp defer_snapshot_publish(term), do: assign(term, deferred_snapshot_publish?: true)

  defp flush_deferred_snapshot_publish(term) do
    if term.assigns.deferred_snapshot_publish? do
      term
      |> assign(deferred_snapshot_publish?: false)
      |> maybe_publish_presentation()
    else
      term
    end
  end

  defp cancel_live_snapshot_request(term) do
    case term.assigns.live_snapshot_request do
      %{timeout_ref: timeout_ref} -> cancel_timer(timeout_ref)
      _other -> :ok
    end

    assign(term, live_snapshot_request: nil, deferred_snapshot_publish?: false)
  end

  defp cancel_timer(timer_ref) when is_reference(timer_ref) do
    Process.cancel_timer(timer_ref)
    :ok
  end

  defp cancel_timer(_timer_ref), do: :ok

  defp normalize_live_snapshot(%{content: content} = snapshot, fallback_id)
       when is_binary(content) do
    %{
      id: Map.get(snapshot, :id, fallback_id),
      content: content,
      width: Map.get(snapshot, :width),
      height: Map.get(snapshot, :height)
    }
  end

  defp normalize_live_snapshot(_snapshot, _fallback_id), do: nil

  defp child_live_snapshot(term, id) do
    with %{pid: pid} when is_pid(pid) <- Map.get(term.children, id),
         true <- Process.alive?(pid) do
      width = max(term.assigns.screen_width - 6, 20)
      height = max(term.assigns.screen_height - 6, 8)
      terminal = snapshot_terminal(term.terminal, width, height)

      case Breeze.ChildServer.render_snapshot(pid,
             focused: strip_live_focus(term.focused, id),
             implicit_state: %{},
             terminal: terminal,
             theme: term.theme,
             theme_source: term.theme_source || term.theme,
             live_prefix: id
           ) do
        {:ok, _acc, box, _decorations} ->
          %{
            id: id,
            content: box.content || "",
            width: box.width || width,
            height: box.height || height
          }

        _other ->
          nil
      end
    else
      _other -> nil
    end
  end

  defp snapshot_terminal(%Termite.Terminal{} = terminal, width, height) do
    %{terminal | size: %{width: width, height: height}}
  end

  defp snapshot_terminal(_terminal, width, height) do
    %Termite.Terminal{size: %{width: width, height: height}}
  end

  defp strip_live_focus(focused, id) when is_binary(focused) and is_binary(id) do
    cond do
      focused == id -> nil
      String.starts_with?(focused, id <> "::") -> String.replace_prefix(focused, id <> "::", "")
      true -> nil
    end
  end

  defp strip_live_focus(_focused, _id), do: nil
end
