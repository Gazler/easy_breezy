defmodule EasyBreezy.Deck.Markdown.Editor do
  @moduledoc false

  alias EasyBreezy.Deck.Markdown

  def save(deck, slide, replacement) when is_binary(replacement) do
    with {:ok, source} <- replace_slide_source(deck, slide, replacement),
         {:ok, edited_deck} <- parse_edited_deck(deck, source),
         {:ok, result} <- write_edited_deck(edited_deck) do
      {:ok, edited_deck, result}
    end
  end

  defp replace_slide_source(
         %{source: source},
         %{source_range: {start, length}},
         replacement
       )
       when is_binary(source) do
    suffix_start = start + length

    {:ok,
     binary_part(source, 0, start) <>
       replacement <>
       binary_part(source, suffix_start, byte_size(source) - suffix_start)}
  end

  defp replace_slide_source(_deck, _slide, _replacement),
    do: {:error, "Slide source is not editable"}

  defp parse_edited_deck(deck, source) do
    opts =
      case deck.source_path do
        path when is_binary(path) -> [base_path: Path.dirname(path), source_path: path]
        _path -> []
      end

    {:ok, Markdown.parse!(source, opts)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp write_edited_deck(%{source_path: path, source: source}) when is_binary(path) do
    case File.write(path, source) do
      :ok -> {:ok, :written}
      {:error, reason} -> {:error, "Could not write #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp write_edited_deck(_deck), do: {:ok, :updated}
end
