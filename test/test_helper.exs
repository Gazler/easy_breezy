breeze_path = Mix.Project.deps_paths() |> Map.fetch!(:breeze)
Code.require_file("test/support/snapshot_assertions.ex", breeze_path)

ExUnit.start()
