defmodule EasyBreezy.Layouts do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Layouts.BulletsSlide
  import EasyBreezy.Layouts.BreezeSlide
  import EasyBreezy.Layouts.CodeSlide
  import EasyBreezy.Layouts.ImageSlide
  import EasyBreezy.Layouts.MarkdownSlide
  import EasyBreezy.Layouts.PresenterSlide
  import EasyBreezy.Layouts.TitleSlide
  import EasyBreezy.Layouts.TwoColumnSlide

  alias EasyBreezy.Layouts.CodeSlide
  alias EasyBreezy.Slide

  attr :slide, :any, required: true
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def slide_source(assigns) do
    source =
      case Map.get(assigns.slide, :source) do
        source when is_binary(source) and source != "" ->
          source

        _source ->
          "No markdown source available for this slide."
      end

    assigns =
      assigns
      |> assign(source: source)
      |> assign(source_title: "#{assigns.slide.title} source")

    ~H"""
    <.code_slide
      title={@source_title}
      language="markdown"
      source={@source}
      path={nil}
      focus_ranges={[]}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    """
  end

  attr :slide, :any, required: true
  attr :step, :integer, required: true
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :live_state, :map, default: %{}
  attr :render_context, :map, default: %{}

  def slide_body(assigns) do
    payload =
      assigns.slide
      |> Slide.resolve_payload(assigns.body_width, assigns.step)
      |> resolve_code_payload(assigns.step)

    assigns =
      assign(assigns,
        slide_payload:
          Map.merge(
            %{
              left_title: nil,
              left_items: [],
              left_lines: [],
              left_mermaid_source: nil,
              left_mode: :text,
              left_path: nil,
              prefix: nil,
              subtitle: nil,
              speaker: nil,
              footer: nil,
              path: nil,
              alt: nil,
              width: nil,
              height: nil,
              title_font: nil,
              font: nil,
              reveal: nil,
              right_title: nil,
              right_lines: [],
              right_mermaid_source: nil,
              right_notice: nil,
              right_mode: :text,
              right_path: nil,
              code_language: nil,
              code_source: nil,
              code_path: nil,
              code_focus_ranges: [],
              view: nil,
              live_id: nil,
              start_opts: [],
              assigns: %{},
              after_markdown: nil,
              breeze_class: "width-full height-full",
              breeze_style: nil,
              breeze_focusable: true,
              markdown: nil,
              markdown_blocks: nil
            },
            payload
          )
      )

    ~H"""
    <.title_slide
      :if={@slide.layout == :title}
      slide_id={@slide.id}
      prefix={@slide_payload.prefix}
      title={@slide_payload.title}
      subtitle={@slide_payload.subtitle}
      speaker={@slide_payload.speaker}
      footer={@slide_payload.footer}
      font={@slide_payload.title_font || @slide_payload.font}
      render_context={@render_context}
    />
    <.bullets_slide
      :if={@slide.layout == :bullets}
      title={@slide_payload.title}
      items={@slide_payload.items}
      after_markdown={@slide_payload.after_markdown}
      reveal={reveal(@slide_payload)}
      step={@step}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    <.image_slide
      :if={@slide.layout == :image}
      path={@slide_payload.path}
      alt={@slide_payload.alt}
      width={@slide_payload.width}
      height={@slide_payload.height}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    <.two_column_slide
      :if={@slide.layout == :two_column}
      title={@slide_payload.title}
      left_title={@slide_payload.left_title}
      left_items={@slide_payload.left_items}
      left_lines={@slide_payload.left_lines}
      left_mermaid_source={@slide_payload[:left_mermaid_source]}
      left_mode={@slide_payload[:left_mode] || :text}
      left_path={@slide_payload[:left_path]}
      right_title={@slide_payload.right_title}
      right_lines={@slide_payload.right_lines}
      right_mermaid_source={@slide_payload[:right_mermaid_source]}
      right_notice={@slide_payload[:right_notice]}
      right_mode={@slide_payload[:right_mode] || :text}
      right_path={@slide_payload[:right_path]}
      reveal={reveal(@slide_payload)}
      step={@step}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    <.presenter_slide
      :if={@slide.layout == :presenter}
      title={@slide_payload.title}
      items={@slide_payload.items}
      notes={@slide_payload.notes}
      reveal={reveal(@slide_payload)}
      step={@step}
      body_height={@body_height}
      render_context={@render_context}
    />
    <.markdown_slide
      :if={@slide.layout == :markdown}
      slide_id={@slide.id}
      title={@slide_payload.title}
      content={@slide_payload.markdown}
      blocks={@slide_payload[:markdown_blocks]}
      step={@step}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    <.code_slide
      :if={@slide.layout == :code}
      title={@slide_payload.title}
      language={@slide_payload.code_language}
      source={@slide_payload.code_source}
      path={@slide_payload.code_path}
      focus_ranges={@slide_payload.code_focus_ranges}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    <.breeze_slide
      :if={@slide.layout == :breeze}
      slide_id={@slide.id}
      view={@slide_payload.view}
      live_id={@slide_payload[:live_id]}
      start_opts={@slide_payload[:start_opts] || []}
      assigns={@slide_payload[:assigns] || %{}}
      live_state={@live_state}
      class={@slide_payload[:breeze_class] || @slide_payload[:class] || "width-full height-full"}
      style={@slide_payload[:breeze_style] || @slide_payload[:style]}
      focusable={@slide_payload[:breeze_focusable] != false}
    />
    """
  end

  defp resolve_code_payload(%{code_focus_ranges: focus_ranges} = payload, step) do
    %{payload | code_focus_ranges: CodeSlide.focus_ranges_for_step(focus_ranges, step)}
  end

  defp resolve_code_payload(payload, _step), do: payload

  defp reveal(payload) do
    Map.get(payload, :reveal, :step)
  end
end
