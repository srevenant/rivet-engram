defmodule Rivet.Engram.Parse do
  @moduledoc false
  alias Rivet.Engram

  @always_imports ["Transmogrify", "Transmogrify.As"]

  @spec parse(Engram.Read.result(), Path.t(), keyword()) ::
          {:ok, Engram.t()} | {:error, term()}

  @doc """
  Internally this receives the piped result from Engram.Read, thus it is using
  the idiomatic tuple shape and passing through errors unchanged.
  """
  def parse({:ok, meta, body}, file, opts) do
    with {:ok, en} <- build_engram(opts, file, meta), do: parse_sections(en, body)
  end

  def parse(pass, _, _), do: pass

  ##############################################################################
  defp build_engram(opts, file, %{sections: meta_index} = meta) do
    # this is a real mess but I'm not sure there's an easier way
    assigns = Map.delete(meta, :sections)

    opts = Map.new(opts) |> prepare_opt_imports()
    opt_index = Map.get(opts, :sections, :all)

    with {:ok, index} <- get_opt_section_index(opt_index, meta_index) do
      # preference given to opts over engram assigns
      assigns = Map.merge(assigns, Map.get(opts, :assigns, %{}))

      imports = Map.get(opts, :imports, [])

      opts = Map.drop(opts, [:sections, :assigns, :imports, :file])

      {:ok, %Engram{index: index, assigns: assigns, opts: opts, imports: imports, file: file}}
    end
  end

  defp build_engram(_, _, _), do: {:error, "Invalid Engram: missing section index"}

  ##############################################################################
  defp get_opt_section_index(:all, meta_index), do: {:ok, meta_index}

  defp get_opt_section_index(list, meta_index) when is_list(list),
    do: {:ok, Map.take(meta_index, list)}

  ### not allowed at this time; maybe in the future
  # defp get_opt_section_index(map, _meta_index) when is_map(map), do: {:ok, map}

  defp get_opt_section_index(_, _),
    do: {:error, "Invalid sections index, not :all or a list of section names as atoms"}

  ##############################################################################
  defp prepare_opt_imports(%{imports: imports} = opts) when is_list(imports),
    do: %{opts | imports: Enum.uniq(@always_imports ++ imports)}

  defp prepare_opt_imports(opts), do: Map.put(opts, :imports, @always_imports)

  ##############################################################################
  defp parse_sections(%Engram{index: index} = en, [{label, body, line} | rest])
       when is_map_key(index, label) do
    with {:ok, %Engram{} = en} <- parse_section(en, label, body, line),
         do: parse_sections(en, rest)
  end

  # not a section which was asked for
  defp parse_sections(%Engram{} = en, [{_, _, _} | rest]), do: parse_sections(en, rest)

  # we are done with the first pass
  defp parse_sections(%Engram{} = en, []), do: {:ok, %{en | deferred: Enum.reverse(en.deferred)}}

  ##############################################################################
  defp parse_section(%Engram{} = en, label, body, line) do
    case en.index[label] do
      "yml" ->
        with {:ok, data} <- parse_yaml(body),
             do: {:ok, %{en | sections: Map.put(en.sections, label, data)}}

      type when type in ["eex-yml", "eex-yml-docs", "eex"] ->
        {:ok, %{en | deferred: [{label, body, line} | en.deferred]}}

      type ->
        {:error, "Invalid section type #{inspect(type)} for #{inspect(label)}"}
    end
  end

  ##############################################################################
  @type yaml_method :: :read_from_string | :read_all_from_string

  @spec parse_yaml(iodata(), yaml_method()) :: {:ok, term()} | {:error, term()}
  @doc false
  def parse_yaml(data, method \\ :read_from_string) do
    with {:ok, data} <- apply(YamlElixir, method, [data]) do
      {:ok, Transmogrify.transmogrify(data)}
    end
  end
end
