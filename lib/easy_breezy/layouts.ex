defmodule EasyBreezy.Layouts do
  @moduledoc false

  use Breeze.View

  import EasyBreezy.Layouts.BulletsSlide
  import EasyBreezy.Layouts.CodeSlide
  import EasyBreezy.Layouts.LiveSlide
  import EasyBreezy.Layouts.PresenterSlide
  import EasyBreezy.Layouts.TitleSlide
  import EasyBreezy.Layouts.TwoColumnSlide

  attr(:slide, :any, required: true)
  attr(:step, :integer, required: true)
  attr(:body_width, :integer, required: true)
  attr(:body_height, :integer, required: true)
  attr(:render_context, :map, default: %{})

  def slide_body(assigns) do
    payload = resolve_slide_payload(assigns.slide, assigns.body_width, assigns.step)

    assigns =
      assign(assigns,
        slide_payload:
          Map.merge(
            %{
              left_title: nil,
              left_items: [],
              left_lines: [],
              right_title: nil,
              right_lines: [],
              right_notice: nil,
              right_mode: :text,
              right_path: nil,
              code_language: nil,
              code_source: nil,
              code_path: nil,
              code_focus_ranges: [],
              live_id: nil,
              view: nil,
              start_opts: [],
              full_bleed: false,
              persistent: false,
              hosted_live: false
            },
            payload
          )
      )

    ~H"""
    <.title_slide
      :if={@slide.layout == :title}
      title={@slide_payload.title}
      subtitle={@slide_payload.subtitle}
      speaker={@slide_payload.speaker}
      footer={@slide_payload.footer}
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
    <.live_slide
      :if={@slide.layout == :live}
      id={@slide_payload.live_id || "slide-live-#{@slide.id}"}
      title={@slide_payload.title}
      view={@slide_payload.view}
      start_opts={@slide_payload.start_opts}
      full_bleed={@slide_payload.full_bleed}
      persistent={@slide_payload.persistent}
      hosted_live={@slide_payload.hosted_live}
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
end
