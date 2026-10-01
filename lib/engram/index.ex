defmodule Rivet.Engram do
  @moduledoc """
  Parses and evaluates Rivet Engram documents.

  Engrams contain named sections which may contain YAML, EEx, or EEx-generated
  YAML. Sections are evaluated in document order and may reference previously
  evaluated sections.

  Use `process_file/2` or `process_string/2` for normal use. The `parse_*`
  functions perform only the initial parsing pass, while `evaluate/1` evaluates
  deferred EEx sections.

  See project README for full information and examples.
  """

  alias __MODULE__

  @type section_name :: atom()
  @type section_index :: %{section_name() => String.t()}
  @type raw_section :: {section_name(), [String.t()], line_number()}
  @type engram_metadata :: map()
  @type line_number :: pos_integer()
  @type engram_diagnostic ::
          %{display: String.t(), diag: map()}
          | %{display: String.t(), trace: list() | nil, error: term()}

  @type t :: %__MODULE__{
          sections: %{section_name() => term()},
          deferred: [raw_section()],
          index: section_index() | :all,
          assigns: map(),
          file: Path.t(),
          imports: [String.t()],
          diags: %{section_name() => [engram_diagnostic()]},
          opts: map()
        }

  defstruct sections: %{},
            deferred: [],
            index: :all,
            assigns: %{},
            file: "nofile",
            imports: [],
            diags: %{},
            opts: %{}

  @spec parse_file(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def parse_file(path, opts \\ []),
    do: Engram.Read.from_file(path) |> Engram.Parse.parse(path, opts)

  @spec process_file(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def process_file(path, opts \\ []) do
    with {:ok, %Engram{} = t} <- parse_file(path, opts), do: evaluate(t)
  end

  @spec parse_string(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def parse_string(string, opts \\ []),
    do: Engram.Read.from_string(string) |> Engram.Parse.parse("nofile", opts)

  @spec process_string(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def process_string(string, opts \\ []) do
    with {:ok, %Engram{} = t} <- parse_string(string, opts), do: evaluate(t)
  end

  @spec evaluate(t()) :: {:ok, t()} | {:error, term()}
  def evaluate(%Engram{} = t), do: Engram.Evaluate.sections(t)
end
