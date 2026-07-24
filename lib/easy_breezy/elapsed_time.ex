defmodule EasyBreezy.ElapsedTime do
  @moduledoc false

  def elapsed_ms(started_at_ms, now_ms \\ System.monotonic_time(:millisecond))

  def elapsed_ms(started_at_ms, now_ms)
      when is_integer(started_at_ms) and is_integer(now_ms) do
    max(now_ms - started_at_ms, 0)
  end

  def elapsed_ms(_started_at_ms, _now_ms), do: 0

  def started_at_ms_from_elapsed(elapsed_ms, now_ms \\ System.monotonic_time(:millisecond))

  def started_at_ms_from_elapsed(elapsed_ms, now_ms)
      when is_integer(elapsed_ms) and is_integer(now_ms) do
    now_ms - max(elapsed_ms, 0)
  end

  def started_at_ms_from_elapsed(_elapsed_ms, now_ms) when is_integer(now_ms), do: now_ms

  def label(started_at_ms, now_ms \\ System.monotonic_time(:millisecond)) do
    started_at_ms
    |> elapsed_ms(now_ms)
    |> label_from_elapsed()
  end

  def label_from_elapsed(elapsed_ms, prefix \\ "Elapsed") do
    total_seconds = div(max(elapsed_ms, 0), 1_000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)

    "#{prefix} #{pad2(minutes)}:#{pad2(seconds)}"
  end

  defp pad2(int) when int >= 0 and int < 10, do: "0#{int}"
  defp pad2(int), do: Integer.to_string(int)
end
