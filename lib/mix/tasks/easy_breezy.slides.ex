defmodule Mix.Tasks.EasyBreezy.Slides do
  @moduledoc """
  Starts the Easy Breezy audience view.

  Pass the slideshow script after the task name:

      mix easy_breezy.slides slides.exs

  Any other `mix run` arguments are forwarded too:

      mix easy_breezy.slides --no-compile talks/demo.exs

  The audience view runs as `slides@127.0.0.1` using long names. EPMD must
  already be running.
  """

  use Mix.Task

  @shortdoc "Starts the Easy Breezy audience view"

  @impl Mix.Task
  def run(args), do: EasyBreezy.MixTask.PresenterMode.run(:slides, args)
end
