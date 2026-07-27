defmodule EasyBreezy.Export.HTML do
  @moduledoc """
  A single-file, keyboard-navigable HTML backend for terminal frames.

  Text is positioned on a CSS cell grid, so the browser does not perform a
  second layout pass over the presentation content. Media is embedded once as
  a data URI and reused through generated CSS classes.
  """

  @behaviour EasyBreezy.Export.Backend

  alias EasyBreezy.Export.{Document, Frame, Media, Run, Style}

  @row_height_em 1.25
  @default_font_family ~s("Cascadia Mono", monospace)
  @default_font_stylesheet "https://fonts.googleapis.com/css2?family=Cascadia+Mono:wght@400;700&display=swap"

  @impl true
  def render(%Document{frames: []}, _opts), do: {:error, :empty_document}

  def render(%Document{} = document, opts) do
    font_family = Keyword.get(opts, :font_family, @default_font_family)
    font_stylesheet = Keyword.get(opts, :font_stylesheet, @default_font_stylesheet)
    font_size = Keyword.get(opts, :font_size, 16)
    {asset_classes, asset_css} = asset_styles(document.frames)
    {style_classes, style_css} = text_styles(document.frames)
    {position_classes, position_css} = position_styles(document.frames)
    {background_classes, background_css} = background_styles(document.frames)

    classes = %{
      assets: asset_classes,
      backgrounds: background_classes,
      positions: position_classes,
      styles: style_classes
    }

    background = document.frames |> List.first() |> Map.get(:background) |> color(:background)

    frames =
      document.frames
      |> Enum.with_index()
      |> Enum.map_join(fn {frame, index} ->
        render_frame(frame, index, classes)
      end)

    html =
      """
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{escape(document.title)}</title>
      #{font_head(font_stylesheet)}
        <style>
      #{base_css(font_family, font_size, background, document.width, document.height)}
      #{background_css}
      #{style_css}
      #{position_css}
      #{asset_css}
        </style>
      </head>
      <body>
        <main id="d" aria-label="#{escape_attribute(document.title)}">
      #{frames}
        </main>
        <script>
      #{navigation_script()}
        </script>
      </body>
      </html>
      """

    {:ok, html}
  end

  defp render_frame(%Frame{} = frame, index, classes) do
    frame_classes = if index == 0, do: "f a", else: "f"
    background_class = Map.fetch!(classes.backgrounds, frame.background)
    hidden = if index == 0, do: "false", else: "true"
    title = frame.title || "Slide #{frame.slide_index + 1}"

    runs =
      Enum.map_join(frame.runs, &render_run(&1, frame.background, classes))

    media = Enum.map_join(frame.media, &render_media(&1, classes.assets))

    ~s(<section class="#{frame_classes} #{background_class}" data-s="#{frame.slide_index}" data-p="#{frame.step}" aria-hidden="#{hidden}" aria-label="#{escape_attribute(title)}, step #{frame.step + 1}">#{runs}#{media}</section>)
  end

  defp render_run(%Run{width: width}, _background, _classes) when width <= 0,
    do: ""

  defp render_run(%Run{} = run, frame_background, classes) do
    if invisible_blank_run?(run, frame_background) do
      ""
    else
      style_class = Map.fetch!(classes.styles, run.style)
      position_class = Map.fetch!(classes.positions, run_position(run))
      text = if blank_run?(run) and not decorated_spaces?(run.style), do: "", else: run.text

      ~s(<span class="r #{style_class} #{position_class}">#{escape(text)}</span>)
    end
  end

  defp render_media(%Media{} = media, asset_classes) do
    asset_class = Map.fetch!(asset_classes, asset_key(media))

    style =
      "grid-column: #{media.x + 1} / span #{max(media.width, 1)}; " <>
        "grid-row: #{media.y + 1} / span #{max(media.height, 1)}"

    ~s(<div class="m #{asset_class}" role="img" aria-label="#{escape_attribute(media.alt)}" style="#{style}"></div>)
  end

  defp text_styles(frames) do
    frames
    |> Enum.flat_map(& &1.runs)
    |> Enum.map(& &1.style)
    |> indexed_styles("s", fn style -> style |> text_style() |> Enum.join(";") end)
  end

  defp position_styles(frames) do
    frames
    |> Enum.flat_map(& &1.runs)
    |> Enum.filter(&(&1.width > 0))
    |> Enum.map(&run_position/1)
    |> indexed_styles("p", fn {column, row, width} ->
      "grid-area:#{row}/#{column}/auto/span #{width}"
    end)
  end

  defp background_styles(frames) do
    frames
    |> Enum.map(& &1.background)
    |> indexed_styles("b", &"background-color:#{color(&1, :background)}")
  end

  defp indexed_styles(values, prefix, declaration),
    do: indexed_styles(values, prefix, declaration, &Function.identity/1)

  defp indexed_styles(values, prefix, declaration, key) do
    entries =
      values
      |> Enum.uniq_by(key)
      |> Enum.with_index()
      |> Enum.map(fn {value, index} -> {key.(value), value, "#{prefix}#{index}"} end)

    classes = Map.new(entries, fn {key, _value, class} -> {key, class} end)

    css =
      Enum.map_join(entries, fn {_key, value, class} ->
        ".#{class}{#{declaration.(value)}}"
      end)

    {classes, css}
  end

  defp run_position(%Run{} = run), do: {run.x + 1, run.y + 1, max(run.width, 1)}

  defp invisible_blank_run?(%Run{} = run, frame_background) do
    blank_run?(run) and not decorated_spaces?(run.style) and
      Style.effective_background(run.style) in [nil, frame_background]
  end

  defp blank_run?(%Run{text: text}), do: String.trim(text) == ""

  defp decorated_spaces?(%Style{} = style),
    do: style.underline or style.crossed_out

  defp text_style(%Style{} = style) do
    {foreground, background} =
      if style.inverse do
        {style.background, style.foreground}
      else
        {style.foreground, style.background}
      end

    []
    |> maybe_style(foreground, fn value -> "color: #{color(value, :foreground)}" end)
    |> maybe_style(background, fn value -> "background-color: #{color(value, :background)}" end)
    |> maybe_style(style.bold, fn -> "font-weight: 700" end)
    |> maybe_style(style.faint, fn -> "opacity: 0.72" end)
    |> maybe_style(style.italic, fn -> "font-style: italic" end)
    |> maybe_style(style.blink, fn -> "animation: eb-blink 1s step-end infinite" end)
    |> maybe_text_decoration(style)
  end

  defp maybe_style(styles, nil, _fun), do: styles
  defp maybe_style(styles, false, _fun), do: styles
  defp maybe_style(styles, true, fun) when is_function(fun, 0), do: [fun.() | styles]
  defp maybe_style(styles, value, fun) when is_function(fun, 1), do: [fun.(value) | styles]

  defp maybe_text_decoration(styles, style) do
    decorations =
      []
      |> maybe_decoration(style.underline, "underline")
      |> maybe_decoration(style.crossed_out, "line-through")

    case decorations do
      [] -> styles
      values -> ["text-decoration: #{Enum.join(values, " ")}" | styles]
    end
  end

  defp maybe_decoration(values, true, decoration), do: [decoration | values]
  defp maybe_decoration(values, _enabled, _decoration), do: values

  defp asset_styles(frames) do
    frames
    |> Enum.flat_map(& &1.media)
    |> indexed_styles(
      "i",
      fn media ->
        encoded = Base.encode64(media.data)
        ~s|background-image:url("data:#{media.mime_type};base64,#{encoded}")|
      end,
      &asset_key/1
    )
  end

  defp asset_key(%Media{mime_type: mime_type, data: data}), do: {mime_type, data}

  defp base_css(font_family, font_size, background, width, height) do
    frame_height = height * @row_height_em

    """
    :root {
      color-scheme: dark;
      background: #{background};
    }

    * { box-sizing: border-box; }

    html, body {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #{background};
    }

    body {
      font-family: #{font_family};
      font-size: #{font_size}px;
      font-variant-ligatures: none;
      text-rendering: geometricPrecision;
    }

    #d {
      position: relative;
      width: 100vw;
      height: 100vh;
      overflow: hidden;
      background: #{background};
      user-select: text;
    }

    .f {
      position: absolute;
      left: 50%;
      top: 50%;
      display: none;
      width: #{width}ch;
      height: #{frame_height}em;
      grid-template-columns: repeat(#{width}, 1ch);
      grid-template-rows: repeat(#{height}, #{@row_height_em}em);
      transform-origin: center center;
      isolation: isolate;
    }

    .f.a { display: grid; }

    .r {
      z-index: 1;
      display: block;
      min-width: 0;
      height: #{@row_height_em}em;
      margin: 0;
      padding: 0;
      overflow: visible;
      white-space: pre;
      line-height: #{@row_height_em}em;
    }

    .m {
      z-index: 2;
      width: 100%;
      height: 100%;
      background-position: center;
      background-repeat: no-repeat;
      background-size: contain;
    }

    @keyframes eb-blink { 50% { visibility: hidden; } }

    @media (prefers-reduced-motion: reduce) {
      .r { animation: none !important; }
    }

    @media print {
      html, body {
        width: auto;
        height: auto;
        overflow: visible;
      }

      #d {
        width: auto;
        height: auto;
        overflow: visible;
      }

      .f {
        position: relative;
        left: 0;
        top: 0;
        display: grid !important;
        transform: none !important;
        break-after: page;
        page-break-after: always;
      }
    }
    """
  end

  defp navigation_script do
    """
    (() => {
      const frames = Array.from(document.querySelectorAll('.f'));
      if (frames.length === 0) return;

      let current = 0;

      const requestedFrame = () => {
        const match = window.location.hash.match(/^#(\\d+)\\.(\\d+)$/);
        if (!match) return 0;
        const slide = Number(match[1]) - 1;
        const step = Number(match[2]) - 1;
        const index = frames.findIndex(frame =>
          Number(frame.dataset.s) === slide && Number(frame.dataset.p) === step
        );
        return index < 0 ? 0 : index;
      };

      const fit = () => {
        const frame = frames[current];
        const padding = 24;
        const scale = Math.min(
          (window.innerWidth - padding * 2) / frame.offsetWidth,
          (window.innerHeight - padding * 2) / frame.offsetHeight
        );
        frame.style.transform = `translate(-50%, -50%) scale(${Math.max(scale, 0.01)})`;
      };

      const show = index => {
        current = Math.max(0, Math.min(index, frames.length - 1));
        frames.forEach((frame, frameIndex) => {
          const active = frameIndex === current;
          frame.classList.toggle('a', active);
          frame.setAttribute('aria-hidden', active ? 'false' : 'true');
          if (!active) frame.style.transform = '';
        });

        const frame = frames[current];
        const hash = `#${Number(frame.dataset.s) + 1}.${Number(frame.dataset.p) + 1}`;
        history.replaceState(null, '', hash);
        requestAnimationFrame(fit);
      };

      const next = () => show(current + 1);
      const previous = () => show(current - 1);

      document.addEventListener('keydown', event => {
        if (['ArrowRight', 'ArrowDown', 'PageDown', 'Enter', ' '].includes(event.key)) {
          event.preventDefault();
          next();
        } else if (['ArrowLeft', 'ArrowUp', 'PageUp', 'Backspace'].includes(event.key)) {
          event.preventDefault();
          previous();
        } else if (event.key === 'Home') {
          event.preventDefault();
          show(0);
        } else if (event.key === 'End') {
          event.preventDefault();
          show(frames.length - 1);
        } else if (event.key.toLowerCase() === 'f') {
          event.preventDefault();
          if (document.fullscreenElement) document.exitFullscreen();
          else document.documentElement.requestFullscreen?.();
        }
      });

      document.addEventListener('click', event => {
        if (!window.getSelection().isCollapsed) return;
        if (event.clientX < window.innerWidth / 2) previous();
        else next();
      });

      window.addEventListener('resize', fit);
      document.fonts?.ready.then(fit);
      show(requestedFrame());
    })();
    """
  end

  defp color(nil, :background), do: "#000000"

  defp color({red, green, blue}, _role) do
    "#" <> hex_byte(red) <> hex_byte(green) <> hex_byte(blue)
  end

  defp hex_byte(value), do: value |> Integer.to_string(16) |> String.pad_leading(2, "0")

  defp font_head(nil), do: ""

  defp font_head(stylesheet) when is_binary(stylesheet) do
    ~s(<link href="#{escape_attribute(stylesheet)}" rel="stylesheet">)
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attribute(value) do
    value
    |> escape()
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
