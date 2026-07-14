defmodule EasyBreezy.ThemeContext do
  @moduledoc false

  alias Breeze.Theme
  alias EasyBreezy.Layouts.CodeSlide

  @color_roles [:bg, :text, :primary, :secondary, :muted, :accent, :panel, :surface, :stroke]

  def from_term(%{theme: theme} = term) do
    assigns = Map.get(term, :assigns, %{})
    metadata = theme_metadata(assigns)

    derive(theme,
      theme_name: Map.get(metadata, :name) || Map.get(assigns, :theme_name) || :nebula,
      actual_theme_mode: Map.get(metadata, :actual_mode),
      theme_status: Map.get(metadata, :status)
    )
  end

  def derive(theme, options \\ []) do
    theme = Theme.new(theme)
    theme_name = Keyword.get(options, :theme_name) || :nebula

    %{
      theme_name: theme_name,
      actual_theme_mode: Keyword.get(options, :actual_theme_mode) || theme.mode,
      theme_status: Keyword.get(options, :theme_status) || Theme.probe_status(theme) || :ready,
      code_theme: CodeSlide.lumis_theme_name(theme_name),
      theme_colors: Map.new(@color_roles, &{&1, Theme.color(theme, &1)})
    }
  end

  defp theme_metadata(assigns) when is_map(assigns) do
    case get_in(assigns, [:breeze, :theme]) do
      metadata when is_map(metadata) -> metadata
      _metadata -> %{}
    end
  end

  defp theme_metadata(_assigns), do: %{}
end
