defmodule Mix.Tasks.EasyBreezy.Presenter do
  @moduledoc """
  Starts the Easy Breezy presenter view.

  Pass the slideshow script after the task name:

      mix easy_breezy.presenter slides.exs

  Any other `mix run` arguments are forwarded too:

      mix easy_breezy.presenter --no-compile talks/demo.exs

  The presenter view runs as `presenter@127.0.0.1` using long names. EPMD must
  already be running.
  """

  use Mix.Task

  @shortdoc "Starts the Easy Breezy presenter view"

  @impl Mix.Task
  def run(args), do: EasyBreezy.MixTask.PresenterMode.run(:presenter, args)
end
