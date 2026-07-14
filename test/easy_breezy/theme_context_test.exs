defmodule EasyBreezy.ThemeContextTest do
  use ExUnit.Case, async: true

  alias Breeze.Theme
  alias EasyBreezy.ThemeContext

  test "derives rendering styles from the active theme" do
    theme = Theme.builtin(:nebula)
    context = ThemeContext.derive(theme, theme_name: :nebula)

    assert context.theme_name == :nebula
    assert context.actual_theme_mode == theme.mode
    assert context.theme_status == :ready
    assert context.code_theme == "cyberdream_dark"

    assert context.theme_colors == %{
             bg: Theme.color(theme, :bg),
             text: Theme.color(theme, :text),
             primary: Theme.color(theme, :primary),
             secondary: Theme.color(theme, :secondary),
             muted: Theme.color(theme, :muted),
             accent: Theme.color(theme, :accent),
             panel: Theme.color(theme, :panel),
             surface: Theme.color(theme, :surface),
             stroke: Theme.color(theme, :stroke)
           }
  end

  test "prefers Breeze theme metadata over stale view assigns" do
    theme = Theme.builtin(:nord)

    context =
      ThemeContext.from_term(%{
        theme: theme,
        assigns: %{
          theme_name: :dracula,
          breeze: %{theme: %{name: :nord, actual_mode: :system, status: :pending}}
        }
      })

    assert context.theme_name == :nord
    assert context.actual_theme_mode == :system
    assert context.theme_status == :pending
    assert context.code_theme == "nordfox"
    assert context.theme_colors.primary == Theme.color(theme, :primary)
  end

  test "falls back to view and active-theme state without Breeze metadata" do
    theme = Theme.builtin(:dracula)

    context =
      ThemeContext.from_term(%{
        theme: theme,
        assigns: %{theme_name: :dracula}
      })

    assert context.theme_name == :dracula
    assert context.actual_theme_mode == theme.mode
    assert context.theme_status == :ready
    assert context.code_theme == "dracula"
  end
end
