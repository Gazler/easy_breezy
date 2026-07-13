defmodule EasyBreezy.Layouts.ImageSlide do
  @moduledoc false

  use Breeze.View

  attr :path, :string, required: true
  attr :alt, :string, default: nil
  attr :width, :integer, default: nil
  attr :height, :integer, default: nil
  attr :body_width, :integer, required: true
  attr :body_height, :integer, required: true
  attr :render_context, :map, default: %{}

  def image_slide(assigns) do
    image_active? = Map.get(assigns.render_context, :render_images?, true) != false
    image_scope = Map.get(assigns.render_context, :image_scope, "slide")
    alt = Map.get(assigns, :alt) || image_fallback(assigns.path)
    canvas_width = max(assigns.body_width + 4, 1)
    canvas_height = max(assigns.body_height + 2, 1)

    {image_width, image_height} =
      image_dimensions(
        Map.get(assigns, :width),
        Map.get(assigns, :height),
        canvas_width,
        canvas_height
      )

    image_style = %{
      position: :absolute,
      left: div(canvas_width - image_width, 2),
      top: div(canvas_height - image_height, 2),
      width: image_width,
      height: image_height
    }

    assigns =
      assign(assigns,
        alt: alt,
        image_active?: image_active?,
        image_scope: image_scope,
        image_style: image_style
      )

    ~H"""
    <box class="width-full height-full bg-panel overflow-hidden">
      <box
        id="slide-image"
        implicit={EasyBreezy.Slideshow.KittyImage}
        image-path={@path}
        image-mode="show"
        image-active={@image_active?}
        image-scope={"#{@image_scope}:full"}
        image-inset={0}
        style={@image_style}
        class="bg-panel text-muted overflow-hidden"
      >
        {@alt}
      </box>
    </box>
    """
  end

  defp image_dimensions(width, height, available_width, available_height)
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    cond do
      width <= available_width and height <= available_height ->
        {width, height}

      available_width * height <= available_height * width ->
        {available_width, max(div(height * available_width, width), 1)}

      true ->
        {max(div(width * available_height, height), 1), available_height}
    end
  end

  defp image_dimensions(width, _height, available_width, available_height)
       when is_integer(width) and width > 0,
       do: {min(width, available_width), available_height}

  defp image_dimensions(_width, height, available_width, available_height)
       when is_integer(height) and height > 0,
       do: {available_width, min(height, available_height)}

  defp image_dimensions(_width, _height, available_width, available_height),
    do: {available_width, available_height}

  defp image_fallback(path) when is_binary(path), do: "Image: #{Path.basename(path)}"
  defp image_fallback(_path), do: "Image unavailable"
end
