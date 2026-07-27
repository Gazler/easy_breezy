defmodule EasyBreezy.Export.Source do
  @moduledoc false

  alias EasyBreezy.{Deck, Slide}
  alias EasyBreezy.Export.{ANSI, Document, MediaResolver}

  @default_size {100, 30}
  @default_theme :nebula

  def capture(deck_input, opts \\ []) when is_list(opts) do
    with {:ok, deck} <- resolve_deck(deck_input),
         :ok <- validate_deck(deck),
         {:ok, config} <- normalize_capture_options(opts),
         {:ok, normalized_deck} <- normalized_deck(deck, config),
         {:ok, frames} <- capture_frames(normalized_deck, config) do
      {width, height} = config.size

      {:ok,
       %Document{
         title: normalized_deck.title || "Untitled Deck",
         width: width,
         height: height,
         frames: frames,
         metadata: %{
           source_path: normalized_deck.source_path,
           theme: config.theme,
           steps: config.step_policy
         }
       }}
    end
  rescue
    error -> {:error, {:capture_failed, error, __STACKTRACE__}}
  end

  defp resolve_deck(%Deck{} = deck), do: {:ok, deck}

  defp resolve_deck({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    {:ok, apply(module, function, args)}
  end

  defp resolve_deck(deck) when is_function(deck, 0), do: {:ok, deck.()}

  defp resolve_deck(path) when is_binary(path) do
    if EasyBreezy.Deck.Markdown.markdown_path?(path) do
      {:ok, EasyBreezy.Deck.Markdown.load!(path)}
    else
      {:error, {:unsupported_deck_path, path}}
    end
  end

  defp resolve_deck(other), do: {:error, {:invalid_deck, other}}

  defp validate_deck(%Deck{slides: [_slide | _slides]}), do: :ok
  defp validate_deck(%Deck{slides: []}), do: {:error, :empty_deck}
  defp validate_deck(%Deck{}), do: {:error, :invalid_slides}
  defp validate_deck(other), do: {:error, {:invalid_deck, other}}

  defp normalize_size({width, height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0,
       do: {:ok, {width, height}}

  defp normalize_size(%{width: width, height: height}), do: normalize_size({width, height})
  defp normalize_size(size), do: {:error, {:invalid_size, size}}

  defp normalize_step_policy(policy) when policy in [:all, :first, :last], do: {:ok, policy}
  defp normalize_step_policy(policy), do: {:error, {:invalid_step_policy, policy}}

  defp normalize_capture_options(opts) do
    with {:ok, size} <- normalize_size(Keyword.get(opts, :size, @default_size)),
         {:ok, step_policy} <- normalize_step_policy(Keyword.get(opts, :steps, :all)) do
      theme = Keyword.get(opts, :theme, @default_theme)

      {:ok,
       %{
         size: size,
         step_policy: step_policy,
         theme: theme,
         theme_source: resolve_theme_source(theme)
       }}
    end
  end

  defp normalized_deck(deck, config) do
    with_session(deck, {0, 0}, config, fn session ->
      case Breeze.Test.metadata(session) do
        %{assigns: %{deck: %Deck{} = normalized_deck}} -> {:ok, normalized_deck}
        metadata -> {:error, {:missing_normalized_deck, metadata}}
      end
    end)
  end

  defp capture_frames(deck, config) do
    deck.slides
    |> Enum.with_index()
    |> Enum.flat_map(fn {%Slide{} = slide, slide_index} ->
      Enum.map(steps_for(slide, config.step_policy), &{slide, slide_index, &1})
    end)
    |> Enum.reduce_while({:ok, []}, fn {%Slide{} = slide, _slide_index, _step} = target,
                                       {:ok, frames} ->
      case capture_frame(deck, target, config) do
        {:ok, frame} ->
          {:cont, {:ok, [frame | frames]}}

        {:error, reason} when slide.layout == :breeze ->
          case capture_live_placeholder(deck, target, config, reason) do
            {:ok, frame} -> {:cont, {:ok, [frame | frames]}}
            {:error, fallback_reason} -> {:halt, {:error, fallback_reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, frames} -> {:ok, Enum.reverse(frames)}
      error -> error
    end
  end

  defp steps_for(%Slide{steps: steps}, :all) when is_integer(steps) and steps >= 0,
    do: Enum.to_list(0..steps)

  defp steps_for(%Slide{}, :first), do: [0]

  defp steps_for(%Slide{steps: steps}, :last) when is_integer(steps) and steps >= 0,
    do: [steps]

  defp steps_for(%Slide{}, _policy), do: [0]

  defp capture_frame(
         deck,
         {%Slide{} = slide, slide_index, step},
         %{size: {width, height}} = config
       ) do
    try do
      with_session(deck, {slide_index, step}, config, fn session ->
        render_opts = [
          terminal: session.terminal,
          implicit_state: %{},
          theme_source: config.theme_source
        ]

        case Breeze.ChildServer.render_snapshot(session.pid, render_opts) do
          {:ok, _acc, box, decorations} ->
            media = MediaResolver.resolve(decorations)

            {:ok,
             ANSI.parse(box,
               width: width,
               height: height,
               media: media,
               slide_id: slide.id,
               title: slide.title,
               slide_index: slide_index,
               step: step,
               metadata: %{live?: slide.layout == :breeze, layout: slide.layout}
             )}

          {:crash, crash} ->
            {:error, {:render_crash, slide.id, step, crash}}

          other ->
            {:error, {:unexpected_render_result, slide.id, step, other}}
        end
      end)
    rescue
      error -> {:error, {:render_exception, slide.id, step, error}}
    catch
      :exit, reason -> {:error, {:render_exit, slide.id, step, reason}}
    end
  end

  defp capture_live_placeholder(
         deck,
         {%Slide{} = slide, slide_index, step},
         config,
         reason
       ) do
    title = slide.title || "Interactive slide"

    fallback_slide = %Slide{
      slide
      | layout: :bullets,
        steps: 0,
        disable_transitions?: true,
        payload: %{
          title: title,
          items: [
            "Interactive slide",
            "Its initial state was unavailable while exporting."
          ],
          reveal: :immediate
        }
    }

    fallback_deck =
      %{deck | slides: List.replace_at(deck.slides, slide_index, fallback_slide)}

    case capture_frame(fallback_deck, {fallback_slide, slide_index, step}, config) do
      {:ok, frame} ->
        {:ok,
         %{
           frame
           | slide_id: slide.id,
             title: slide.title,
             metadata: %{
               live?: true,
               layout: :breeze,
               snapshot: :unavailable,
               reason: inspect(reason, limit: 10, printable_limit: 300)
             }
         }}

      {:error, fallback_reason} ->
        {:error, {:live_placeholder_failed, slide.id, reason, fallback_reason}}
    end
  end

  defp with_session(deck, {slide_index, step}, config, fun) do
    case Breeze.Test.start(EasyBreezy.Slideshow,
           size: config.size,
           theme: config.theme_source,
           start_opts: [
             deck: deck,
             slide_index: slide_index,
             step: step,
             theme: config.theme
           ]
         ) do
      {:ok, session} ->
        try do
          fun.(session)
        after
          Breeze.Test.stop(session)
        end

      {:error, reason} ->
        {:error, {:session_start_failed, slide_index, step, reason}}
    end
  end

  defp resolve_theme_source({_name, theme_source}), do: theme_source
  defp resolve_theme_source(theme) when theme in [:system16, :system], do: theme
  defp resolve_theme_source(theme) when is_atom(theme), do: Breeze.Theme.builtin(theme)
  defp resolve_theme_source(theme), do: theme
end
