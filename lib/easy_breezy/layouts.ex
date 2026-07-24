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

  def slide_body(%{slide: %{layout: :title}} = assigns) do
    assigns = assign_payload(assigns)

    ~H"""
    <.title_slide
      slide_id={@slide.id}
      prefix={@payload[:prefix]}
      title={@payload.title}
      subtitle={@payload[:subtitle]}
      speaker={@payload[:speaker]}
      footer={@payload[:footer]}
      font={@payload[:title_font] || @payload[:font]}
      render_context={@render_context}
    />
    """
  end

  def slide_body(%{slide: %{layout: :bullets}} = assigns) do
    assigns = assign_payload(assigns)

    ~H"""
    <.bullets_slide
      title={@payload.title}
      items={@payload.items}
      after_markdown={@payload[:after_markdown]}
      reveal={reveal(@payload)}
      step={@step}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    """
  end

  def slide_body(%{slide: %{layout: :image}} = assigns) do
    assigns = assign_payload(assigns)

    ~H"""
    <.image_slide
      path={@payload.path}
      alt={@payload[:alt]}
      width={@payload[:width]}
      height={@payload[:height]}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    """
  end

  def slide_body(%{slide: %{layout: :two_column}} = assigns) do
    assigns = assign_payload(assigns)

    ~H"""
    <.two_column_slide
      title={@payload.title}
      left_title={@payload[:left_title]}
      left_items={@payload[:left_items] || []}
      left_lines={@payload[:left_lines] || []}
      left_mermaid_source={@payload[:left_mermaid_source]}
      left_mode={@payload[:left_mode] || :text}
      left_path={@payload[:left_path]}
      right_title={@payload[:right_title]}
      right_lines={@payload[:right_lines] || []}
      right_mermaid_source={@payload[:right_mermaid_source]}
      right_notice={@payload[:right_notice]}
      right_mode={@payload[:right_mode] || :text}
      right_path={@payload[:right_path]}
      reveal={reveal(@payload)}
      step={@step}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    """
  end

  def slide_body(%{slide: %{layout: :presenter}} = assigns) do
    assigns = assign_payload(assigns)

    ~H"""
    <.presenter_slide
      title={@payload.title}
      items={@payload.items}
      notes={@payload.notes}
      reveal={reveal(@payload)}
      step={@step}
      body_height={@body_height}
      render_context={@render_context}
    />
    """
  end

  def slide_body(%{slide: %{layout: :markdown}} = assigns) do
    assigns = assign_payload(assigns)

    ~H"""
    <.markdown_slide
      slide_id={@slide.id}
      title={@payload[:title]}
      content={@payload.markdown}
      blocks={@payload[:markdown_blocks]}
      step={@step}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    """
  end

  def slide_body(%{slide: %{layout: :code}} = assigns) do
    assigns = assign_payload(assigns)

    ~H"""
    <.code_slide
      title={@payload.title}
      language={@payload[:code_language]}
      source={@payload[:code_source]}
      path={@payload[:code_path]}
      focus_ranges={@payload[:code_focus_ranges] || []}
      body_width={@body_width}
      body_height={@body_height}
      render_context={@render_context}
    />
    """
  end

  def slide_body(%{slide: %{layout: :breeze}} = assigns) do
    assigns = assign_payload(assigns)

    ~H"""
    <.breeze_slide
      slide_id={@slide.id}
      view={@payload.view}
      live_id={@payload[:live_id]}
      start_opts={@payload[:start_opts] || []}
      assigns={@payload[:assigns] || %{}}
      live_state={@live_state}
      class={@payload[:breeze_class] || @payload[:class] || "width-full height-full"}
      style={@payload[:breeze_style] || @payload[:style]}
      focusable={@payload[:breeze_focusable] != false}
    />
    """
  end

  def slide_body(assigns) do
    ~H"""
    """
  end

  defp assign_payload(assigns) do
    payload =
      assigns.slide
      |> resolve_slide_payload(assigns.body_width, assigns.step)
      |> resolve_code_payload(assigns.step)

    assign(assigns, payload: payload)
  end

  defp resolve_slide_payload(%{payload: payload}, body_width, step) when is_function(payload, 2),
    do: payload.(body_width, step)

  defp resolve_slide_payload(%{layout: :breeze, payload: view}, _body_width, _step)
       when is_atom(view),
       do: %{view: view}

  defp resolve_slide_payload(%{payload: payload}, _body_width, _step) when is_map(payload),
    do: payload

  defp resolve_slide_payload(_slide, _body_width, _step), do: %{}

  defp resolve_code_payload(%{code_focus_ranges: focus_ranges} = payload, step) do
    %{payload | code_focus_ranges: CodeSlide.focus_ranges_for_step(focus_ranges, step)}
  end

  defp resolve_code_payload(payload, _step), do: payload

  defp reveal(payload) do
    Map.get(payload, :reveal, :step)
  end
end
