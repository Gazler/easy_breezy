defmodule EasyBreezy.Slide do
  defstruct [
    :id,
    :title,
    :layout,
    :source,
    :source_range,
    :payload,
    steps: 0,
    transition: :slide,
    disable_transitions?: false
  ]
end
