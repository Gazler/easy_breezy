defmodule EasyBreezy.Slide do
  defstruct [
    :id,
    :title,
    :layout,
    :source,
    :payload,
    steps: 0,
    transition: :slide,
    disable_transitions?: false
  ]
end
