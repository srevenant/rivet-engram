defmodule Rivet.Engram.Read do
  @moduledoc false
  alias Rivet.Engram

  @type result :: {:ok, Engram.engram_metadata(), [Engram.raw_section()]} | {:error, term()}

  @spec snake_key(atom() | String.t()) :: atom()
  @doc false
  def snake_key(key) when is_atom(key), do: snake_key(to_string(key))
  def snake_key(key), do: String.trim(key) |> Transmogrify.snakecase() |> String.to_atom()

  ##############################################################################
  @spec from_file(Path.t()) :: result()
  def from_file(path) when is_binary(path) do
    # making it more useful than the erlang error
    with {:error, :enoent} <- stream_file(path),
         do: {:error, "File not found"}
  end

  defp stream_file(path) do
    # unwrapping {:ok, ...}
    with {:ok, result} <-
           File.open(path, [:utf8, :read], fn fd -> process_stream(IO.stream(fd, :line)) end),
         do: result
  end

  ##############################################################################
  @spec from_string(String.t()) :: result()
  def from_string(data) when is_binary(data) do
    with {:ok, pid} <- StringIO.open(data) do
      try do
        process_stream(IO.stream(pid, :line))
      after
        StringIO.close(pid)
      end
    end
  end

  ##############################################################################
  defp process_stream(stream) do
    case reduce_indexed_stream(stream) do
      {{label, start_line, buf}, hist} ->
        [{snake_key(label), Enum.reverse(buf), start_line} | hist]
        |> Enum.reverse()
        |> parse_meta()

      {:error, _} = error ->
        error

      nil ->
        {:error, "Not a Rivet Engram: empty input"}
    end
  end

  ##############################################################################
  defp parse_meta([{:meta, meta, _meta_start} | body]) do
    case YamlElixir.read_from_string(meta) do
      {:ok, meta} when is_map(meta) -> {:ok, Transmogrify.transmogrify(meta), body}
      {:ok, _} -> {:error, "Invalid Engram: metadata must be a map"}
      pass -> pass
    end
  end

  ##############################################################################
  defp reduce_indexed_stream(stream),
    do: stream |> Stream.with_index(1) |> Enum.reduce_while(nil, &read_sections/2)

  ##############################################################################
  defp read_sections({"=== " <> next_label, line}, {{last_label, start_line, buf}, prev}) do
    section = {snake_key(last_label), Enum.reverse(buf), start_line}
    {:cont, {{next_label, line, []}, [section | prev]}}
  end

  defp read_sections({line, _line_nbr}, {{label, start_line, buf}, prev}),
    do: {:cont, {{snake_key(label), start_line, [line | buf]}, prev}}

  defp read_sections({"=== rivet-engram-v1" <> _, line_nbr}, nil),
    do: {:cont, {{:meta, line_nbr, []}, []}}

  # legacy
  defp read_sections({"=== rivet-template-v1" <> _, line_nbr}, nil),
    do: {:cont, {{:meta, line_nbr, []}, []}}

  defp read_sections({line, _line_nbr}, nil),
    do: {:halt, {:error, "Not a Rivet Engram: #{line}"}}
end
