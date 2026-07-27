defmodule EasyBreezy.Export.Style do
  @moduledoc """
  Resolved terminal styling for a run of cells.

  This struct deliberately contains no Breeze or Easy Breezy theme tokens. By
  the time a frame reaches an export backend, all colours have been resolved.
  """

  @type color :: {0..255, 0..255, 0..255} | nil

  @type t :: %__MODULE__{
          foreground: color(),
          background: color(),
          bold: boolean(),
          faint: boolean(),
          italic: boolean(),
          underline: boolean(),
          blink: boolean(),
          inverse: boolean(),
          crossed_out: boolean()
        }

  defstruct foreground: nil,
            background: nil,
            bold: false,
            faint: false,
            italic: false,
            underline: false,
            blink: false,
            inverse: false,
            crossed_out: false

  @doc false
  def effective_background(%__MODULE__{inverse: true, foreground: foreground}), do: foreground
  def effective_background(%__MODULE__{background: background}), do: background
end

defmodule EasyBreezy.Export.Run do
  @moduledoc "A positioned run of terminal text sharing one resolved style."

  @enforce_keys [:x, :y, :width, :text, :style]
  defstruct [:x, :y, :width, :text, :style]

  @type t :: %__MODULE__{
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: non_neg_integer(),
          text: String.t(),
          style: EasyBreezy.Export.Style.t()
        }
end

defmodule EasyBreezy.Export.Media do
  @moduledoc "A binary media asset positioned on a terminal cell rectangle."

  @enforce_keys [:x, :y, :width, :height, :mime_type, :data]
  defstruct [:x, :y, :width, :height, :mime_type, :data, :source, alt: ""]

  @type t :: %__MODULE__{
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer(),
          mime_type: String.t(),
          data: binary(),
          source: String.t() | nil,
          alt: String.t()
        }
end

defmodule EasyBreezy.Export.Frame do
  @moduledoc """
  A format-neutral snapshot of one terminal viewport.

  Frames contain resolved text runs and optional media layers. Backends should
  never need to know which Breeze view or Easy Breezy layout produced them.
  """

  alias EasyBreezy.Export.{Media, Run}

  @enforce_keys [:width, :height]
  defstruct [
    :width,
    :height,
    :background,
    :slide_id,
    :title,
    slide_index: 0,
    step: 0,
    runs: [],
    media: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          background: EasyBreezy.Export.Style.color(),
          slide_id: term(),
          title: String.t() | nil,
          slide_index: non_neg_integer(),
          step: non_neg_integer(),
          runs: [Run.t()],
          media: [Media.t()],
          metadata: map()
        }

  @doc "Returns the visible frame text with ANSI styling removed."
  @spec plain_text(t()) :: String.t()
  def plain_text(%__MODULE__{} = frame) do
    runs_by_row = Enum.group_by(frame.runs, & &1.y)

    0..(frame.height - 1)
    |> Enum.map(fn row ->
      runs_by_row
      |> Map.get(row, [])
      |> Enum.sort_by(& &1.x)
      |> Enum.reduce({[], 0}, fn run, {parts, column} ->
        gap = max(run.x - column, 0)
        next_column = max(column, run.x + run.width)
        {[parts, String.duplicate(" ", gap), run.text], next_column}
      end)
      |> elem(0)
      |> IO.iodata_to_binary()
    end)
    |> Enum.join("\n")
  end
end

defmodule EasyBreezy.Export.Document do
  @moduledoc "A format-neutral collection of exported terminal frames."

  @enforce_keys [:title, :width, :height, :frames]
  defstruct [:title, :width, :height, :frames, metadata: %{}]

  @type t :: %__MODULE__{
          title: String.t(),
          width: pos_integer(),
          height: pos_integer(),
          frames: [EasyBreezy.Export.Frame.t()],
          metadata: map()
        }
end
