defmodule EasyBreezy.Slideshow do
  use Breeze.View

  alias EasyBreezy.Layouts.CodeSlide
  alias EasyBreezy.ElapsedTime
  alias EasyBreezy.LiveSlide
  alias EasyBreezy.PresenterScroll
  import Breeze.Blocks
  import EasyBreezy.Layouts
  import EasyBreezy.Transitions
  alias Breeze.Theme

  @themes Theme.default_cycle()
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
        keybindings_bar?: Keyword.get(opts, :keybindings_bar?, true),
        source_mode?: Keyword.get(opts, :source_mode?, false),
        live_state: %{},
        themes: Keyword.get(opts, :themes, @themes),
        started_at_ms: System.monotonic_time(:millisecond),
        goto_modal?: false,
        goto_slide_input: "",
        goto_slide_error: nil
      )
      |> assign_theme_context()
      |> maybe_put_scroll_keybindings()
      |> maybe_register_presentation()
      |> maybe_publish_presentation_soon()

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
          <box class="text-muted"> {@theme_name}/{@actual_theme_mode} ({@theme_status}) </box>
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
              :if={@source_mode?}
              slide={@slide}
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

  def handle_event(_, %{"key" => "g"}, term) do
    {:noreply, open_goto_slide(term)}
  end

  def handle_event(_, %{"key" => "?"}, term) do
    {:noreply, assign(term, keybindings_bar?: not term.assigns.keybindings_bar?)}
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

  def handle_event(_, %{"key" => key}, term) when key in ["q" | @escape_keys] do
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
    {:noreply, term, invalidate: false}
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

  def handle_info({:easy_breezy_presenter_state_request, pid}, term) when is_pid(pid) do
    if request_server_live_snapshot(term) == :requested do
      :ok
    else
      publish_presentation(term, [pid], presentation_live_snapshot(term))
    end

    {:noreply, term, invalidate: false}
  end

  def handle_info({:breeze_live_snapshot, _ref, id, {:ok, snapshot}}, term)
      when is_binary(id) and is_map(snapshot) do
    if id == visible_live_slide_id(term.assigns) do
      publish_presentation(term, normalize_live_snapshot(snapshot, id))
    end

    {:noreply, term, invalidate: false}
  end

  def handle_info({:breeze_live_snapshot, _ref, id, _reply}, term) do
    if id == visible_live_slide_id(term.assigns) do
      publish_presentation(term, nil)
    end

    {:noreply, term, invalidate: false}
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
       |> focus_visible_live_slide()
       |> maybe_publish_presentation_soon()}
    else
      Process.send_after(self(), :transition_tick, transition.interval_ms)
      {:noreply, assign(term, transition: %{transition | frame: frame})}
    end
  end

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

  defp maybe_register_presentation(%{assigns: %{presenter_mode: :presentation}} = term) do
    EasyBreezy.PresenterSync.register(term.assigns.presenter_sync_name)
    term
  end

  defp maybe_register_presentation(term), do: term

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
    if visible_synced_live_slide?(term.assigns) do
      focus_visible_live_slide(term)
    else
      term
      |> PresenterScroll.apply(PresenterScroll.event(event))
      |> maybe_publish_presentation_soon()
    end
  end

  defp maybe_publish_presentation_soon(%{assigns: %{presenter_mode: :presentation}} = term) do
    send(self(), :publish_presentation_state)
    term
  end

  defp maybe_publish_presentation_soon(term), do: term

  defp maybe_publish_presentation(%{assigns: %{presenter_mode: :presentation}} = term) do
    if request_server_live_snapshot(term) == :requested do
      :ok
    else
      publish_presentation(term, presentation_live_snapshot(term))
    end
  end

  defp maybe_publish_presentation(_term), do: :ok

  defp publish_presentation(term, live_snapshot) do
    publish_presentation(term, ensure_map_set(term.assigns.presenter_subscribers), live_snapshot)
  end

  defp publish_presentation(term, subscribers, live_snapshot) do
    subscribers = ensure_map_set(subscribers)

    if MapSet.size(subscribers) > 0 do
      EasyBreezy.PresenterSync.publish(subscribers, presentation_payload(term, live_snapshot))
    end
  end

  defp maybe_publish_after_render(%{presenter_mode: :presentation} = assigns) do
    if assigns.presenter_subscribers |> ensure_map_set() |> MapSet.size() > 0 do
      send(self(), :publish_presentation_state)
    end

    assigns
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
      theme_name: assigns.theme_name,
      actual_theme_mode: assigns.actual_theme_mode,
      theme_status: assigns.theme_status,
      live_snapshot: live_snapshot,
      scroll_state: PresenterScroll.export(term)
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
  defp ensure_map_set(values) when is_list(values), do: MapSet.new(values)
  defp ensure_map_set(_value), do: MapSet.new()

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

  defp handle_presenter_command(:toggle_source_mode, term) do
    term
    |> toggle_source_mode()
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
    case dispatch_visible_live_input(term, event) do
      {:consumed, term} -> maybe_publish_presentation_soon(term)
      {:not_consumed, term} -> handle_presenter_key_event(event, term)
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

    if slide_index == term.assigns.slide_index do
      term
    else
      jump_to_position(term, slide_index, 0)
    end
  end

  defp jump_to_position(term, slide_index, step) do
    {slide_index, step} = clamped_position(term.assigns.deck, slide_index, step)

    if slide_index == term.assigns.slide_index and step == term.assigns.step do
      term
    else
      do_jump_to_position(term, slide_index, step)
    end
  end

  defp do_jump_to_position(term, slide_index, step) do
    previous_slide = current_slide(term.assigns)

    term
    |> assign(slide_index: slide_index, step: step)
    |> assign(transition: nil)
    |> focus_visible_live_slide()
    |> maybe_delete_image_overlay(previous_slide)
  end

  defp clamp_position(term), do: clamp_position(term, current_slide(term.assigns))

  defp clamp_position(term, previous_slide) do
    deck = term.assigns.deck
    {slide_index, step} = clamped_position(deck, term.assigns.slide_index, term.assigns.step)

    term
    |> assign(slide_index: slide_index, step: step, transition: nil)
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
      |> assign(source_mode?: source_mode?)
      |> focus_visible_live_slide()

    if source_mode? and image_slide?(visible_slide(term.assigns)) do
      EasyBreezy.Slideshow.KittyImage.delete_overlay(term)
    else
      term
    end
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
      ref = make_ref()

      apply(Breeze.Server, :request_live_snapshot, [
        server,
        id,
        self(),
        ref,
        [compact_snapshot: true]
      ])

      :requested
    else
      _other -> :not_requested
    end
  catch
    :exit, _reason -> :not_requested
  end

  defp request_server_live_snapshot(_term), do: :not_requested

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
