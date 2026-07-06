defmodule EasyBreezy.Layouts do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Layouts.BulletsSlide
  import EasyBreezy.Layouts.CodeSlide
  import EasyBreezy.Layouts.PresenterSlide
  import EasyBreezy.Layouts.TitleSlide
  import EasyBreezy.Layouts.TwoColumnSlide

  alias EasyBreezy.Layouts.CodeSlide

  attr(:slide, :any, required: true)
  attr(:step, :integer, required: true)
  attr(:body_width, :integer, required: true)
  attr(:body_height, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def slide_body(assigns) do
    payload =
      assigns.slide
      |> resolve_slide_payload(assigns.body_width, assigns.step)
      |> resolve_code_payload(assigns.step)

    assigns =
      assign(assigns,
        slide_payload:
          Map.merge(
            %{
              left_title: nil,
              left_items: [],
              left_lines: [],
              left_mode: :text,
              left_path: nil,
              subtitle: nil,
              speaker: nil,
              footer: nil,
              title_font: nil,
              font: nil,
              right_title: nil,
              right_lines: [],
              right_notice: nil,
              right_mode: :text,
              right_path: nil,
              code_language: nil,
              code_source: nil,
              code_path: nil,
              code_focus_ranges: []
            },
            payload
          )
      )

    ~H"""
    <.title_slide
      :if={@slide.layout == :title}
      slide_id={@slide.id}
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
      step={@step}
      body_width={@body_width}
      render_context={@render_context}
    />
    <.two_column_slide
      :if={@slide.layout == :two_column}
      title={@slide_payload.title}
      left_title={@slide_payload.left_title}
      left_items={@slide_payload.left_items}
      left_lines={@slide_payload.left_lines}
      left_mode={@slide_payload[:left_mode] || :text}
      left_path={@slide_payload[:left_path]}
      right_title={@slide_payload.right_title}
      right_lines={@slide_payload.right_lines}
      right_notice={@slide_payload[:right_notice]}
      right_mode={@slide_payload[:right_mode] || :text}
      right_path={@slide_payload[:right_path]}
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
      step={@step}
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
    """
  end

  defp resolve_slide_payload(%{payload: payload}, body_width, step) when is_function(payload, 2),
    do: payload.(body_width, step)

  defp resolve_slide_payload(%{payload: payload}, _body_width, _step) when is_map(payload),
    do: payload

  defp resolve_slide_payload(_slide, _body_width, _step), do: %{}

  defp resolve_code_payload(%{code_focus_ranges: focus_ranges} = payload, step) do
    %{payload | code_focus_ranges: CodeSlide.focus_ranges_for_step(focus_ranges, step)}
  end

  defp resolve_code_payload(payload, _step), do: payload
end
