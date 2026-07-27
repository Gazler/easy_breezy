defmodule EasyBreezy.Export.Backend do
  @moduledoc "Behaviour implemented by terminal-document export formats."

  @callback render(EasyBreezy.Export.Document.t(), keyword()) ::
              {:ok, iodata()} | {:error, term()}
end

defmodule EasyBreezy.Export do
  @moduledoc """
  Captures Easy Breezy decks and exports them through format backends.

  HTML exports use a fixed terminal viewport and an explicit theme, preserving
  the same cell layout and resolved colours as the terminal presentation.
  """

  alias EasyBreezy.Export.{Document, HTML, Source}

  @doc "Captures a deck as a format-neutral `EasyBreezy.Export.Document`."
  def capture(deck, opts \\ []), do: Source.capture(deck, opts)

  @doc "Renders a captured document with the selected backend."
  def render(%Document{} = document, backend, opts \\ [])
      when is_atom(backend) and is_list(opts) do
    backend.render(document, opts)
  end

  @doc "Renders a captured document and writes it to `path`."
  def write(%Document{} = document, backend, path, opts \\ [])
      when is_atom(backend) and is_binary(path) and is_list(opts) do
    path = Path.expand(path)

    with {:ok, output} <- render(document, backend, opts),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, output) do
      {:ok, path}
    end
  end

  @doc "Exports a deck to a single HTML file with media embedded."
  def html(deck, opts \\ []) when is_list(opts) do
    output = Keyword.get_lazy(opts, :output, fn -> default_output(deck) end)

    with {:ok, document} <- capture(deck, opts) do
      write(document, HTML, output, opts)
    end
  end

  @doc "Exports a deck to HTML, raising if capture or writing fails."
  def html!(deck, opts \\ []) do
    case html(deck, opts) do
      {:ok, path} -> path
      {:error, reason} -> raise "could not export Easy Breezy deck: #{inspect(reason)}"
    end
  end

  defp default_output(path) when is_binary(path), do: Path.rootname(path) <> ".html"
  defp default_output(_deck), do: Path.expand("presentation.html")
end
