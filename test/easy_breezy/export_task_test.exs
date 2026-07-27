defmodule EasyBreezy.ExportTaskTest do
  use ExUnit.Case, async: false

  setup do
    fixture_dir =
      Path.join(
        System.tmp_dir!(),
        "easy_breezy_export_task_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(fixture_dir)
    on_exit(fn -> File.rm_rf!(fixture_dir) end)

    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous_shell) end)

    {:ok, fixture_dir: fixture_dir}
  end

  test "preserves argv order across expanded require groups", %{fixture_dir: fixture_dir} do
    suffix = System.unique_integer([:positive, :monotonic])
    first_module = "EasyBreezyExportOrderFirst#{suffix}"
    dependency_module = "EasyBreezyExportOrderDependency#{suffix}"
    consumer_module = "EasyBreezyExportOrderConsumer#{suffix}"
    last_module = "EasyBreezyExportOrderLast#{suffix}"

    first_path = Path.join(fixture_dir, "a1.ex")
    dependency_path = Path.join(fixture_dir, "a2.ex")
    consumer_path = Path.join(fixture_dir, "b1.ex")
    last_path = Path.join(fixture_dir, "b2.ex")

    File.write!(first_path, "defmodule #{first_module}, do: def(marker, do: :first)\n")

    File.write!(
      dependency_path,
      "defmodule #{dependency_module}, do: def(marker, do: :dependency)\n"
    )

    File.write!(consumer_path, """
    defmodule #{consumer_module} do
      @dependency #{dependency_module}.marker()
      def marker, do: @dependency
    end
    """)

    File.write!(last_path, "defmodule #{last_module}, do: def(marker, do: :last)\n")

    output_path =
      run_export(fixture_dir, [
        "--require",
        first_path,
        dependency_path,
        "--require",
        consumer_path,
        last_path
      ])

    assert File.exists?(output_path)
    assert apply(Module.concat([first_module]), :marker, []) == :first
    assert apply(Module.concat([consumer_module]), :marker, []) == :dependency
    assert apply(Module.concat([last_module]), :marker, []) == :last
  end

  defp run_export(fixture_dir, require_args) do
    deck_path = Path.join(fixture_dir, "deck.md")
    output_path = Path.join(fixture_dir, "deck.html")

    File.write!(deck_path, """
    ---
    title: Wildcard fixture
    ---
    ---
    layout: title
    title: Exported
    ---
    """)

    Mix.Task.reenable("easy_breezy.export")

    Mix.Tasks.EasyBreezy.Export.run(
      [deck_path, "--theme", "nebula"] ++ require_args ++ ["--output", output_path]
    )

    output_path
  end
end
