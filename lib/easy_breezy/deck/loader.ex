defmodule EasyBreezy.Deck.Loader do
  @moduledoc false

  alias EasyBreezy.Deck.Markdown

  @markdown_extensions [".md", ".markdown"]

  def load!(path, options \\ []) when is_binary(path) and is_list(options) do
    path = Path.expand(path)

    parse_options =
      options
      |> Keyword.put(:base_path, Path.dirname(path))
      |> Keyword.put(:source_path, path)

    path
    |> File.read!()
    |> Markdown.parse!(parse_options)
  end

  def markdown_path?(path) when is_binary(path),
    do: Path.extname(path) in @markdown_extensions

  def markdown_path?(_path), do: false
end
