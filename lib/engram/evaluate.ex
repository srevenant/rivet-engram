defmodule Rivet.Engram.Evaluate do
  @moduledoc false
  alias Rivet.Engram

  @type result ::
          {:ok, term(), [Engram.engram_diagnostic()]}
          | {:error, nil, [Engram.engram_diagnostic()]}

  @spec sections(Engram.t()) :: {:ok, Engram.t()} | {:error, term()}
  def sections(%Engram{deferred: []} = en), do: {:ok, en}
  def sections(%Engram{deferred: deferred} = en), do: eval_sections_(en, deferred)

  ##############################################################################
  defp eval_sections_(%Engram{} = en, [{label, data, offset} | rest]) do
    with {:ok, result, diags} <- eval_section(data, en, offset) do
      yaml_method =
        case en.index[label] do
          "eex-yml" -> :read_from_string
          "eex-yml-docs" -> :read_all_from_string
          "eex" -> :none
        end

      if yaml_method == :none do
        eval_sections_(put_section(en, label, result, diags), rest)
      else
        with {:ok, data} <- Engram.Parse.parse_yaml(result, yaml_method),
             do: eval_sections_(put_section(en, label, data, diags), rest)
      end
    end
  end

  defp eval_sections_(%Engram{} = en, []), do: {:ok, %{en | deferred: []}}

  # # # # # # # # #
  defp put_section(%Engram{} = en, key, result, diags),
    do: %{en | sections: Map.put(en.sections, key, result), diags: Map.put(en.diags, key, diags)}

  ##############################################################################
  @spec eval_section(iodata(), Engram.t(), pos_integer()) :: result()
  defp eval_section(iolist_data, %Engram{} = en, offset) when is_list(iolist_data),
    do: Enum.join(iolist_data) |> eval_section(en, offset)

  defp eval_section(data, %Engram{} = en, offset) do
    # merging sections into assigns here means order matters
    bindings = [assigns: Map.put(en.assigns, :sections, en.sections)]

    case eval_with_diag(data, bindings, en.imports, en.file, offset) do
      {{:ok, evaluated}, diags} ->
        status = if diag_error?(diags), do: :error, else: :ok
        {status, evaluated, Enum.map(diags, &format_diag/1)}

      {{:error, error, trace}, diags} ->
        {:error, nil, simplify_diags(diags, error, trace)}
    end
  end

  ##############################################################################
  defp eval_with_diag(engram_str, bindings, imports, file, line) do
    Code.with_diagnostics(fn ->
      try do
        case eval_env(imports, file, line) do
          {:ok, env} ->
            # do it in two steps so we can easily inject imports without altering line numbers
            quoted = EEx.compile_string(engram_str, file: file, line: line)
            {evaluated, _binding} = Code.eval_quoted(quoted, bindings, env)

            {:ok, evaluated}

          {:error, what} ->
            {:error, what, nil}
        end
      catch
        kind, reason -> {:error, {:catch, kind, reason}, __STACKTRACE__}
      end
    end)
  end

  # # # # # # # # #
  defp eval_env(imports, file, line) do
    env = Code.env_for_eval(file: file, line: line)

    Enum.reduce_while(imports, {:ok, env}, fn module_name, {:ok, env} ->
      with {:ok, mod} <- as_module_or_halt(module_name) do
        case Macro.Env.define_import(env, [line: line], mod, emit_warnings: false) do
          {:ok, env} -> {:cont, {:ok, env}}
          # coveralls-ignore-next-line
          {:error, message} -> {:halt, {:error, "Failed to import module: #{mod}: #{message}"}}
        end
      end
    end)
  end

  # # # # # # # # #
  defp as_module_or_halt(mod) do
    {:ok, Module.safe_concat([mod])}
  rescue
    _ -> {:halt, {:error, "Invalid import module name '#{mod}'"}}
  end

  ##############################################################################
  defp diag_error?(diags), do: Enum.any?(diags, &(&1.severity == :error))

  ##############################################################################
  # a lot of gymnastics from here on down to make useful errors for humans
  defp simplify_diags([], error, trace), do: [format_error(error, trace)]

  defp simplify_diags(diags, error, trace) do
    messages = Enum.map(diags, &format_diag/1)

    # If diagnostics contain an actual compiler error, that should already
    # describe the exception. Otherwise retain the runtime exception too.
    if diag_error?(diags) do
      messages
    else
      messages ++ [format_error(error, trace)]
    end
  end

  ##############################################################################
  defp format_diag(%{message: message, position: {line, _}} = d),
    do: %{display: "Line #{line}: #{message}", diag: d}

  # coveralls-ignore-start
  defp format_diag(%{message: message, position: line} = d) when is_integer(line) and line > 0,
    do: %{display: "Line #{line}: #{message}", diag: d}

  defp format_diag(%{message: message, position: 0} = d), do: %{display: message, diag: d}
  # coveralls-ignore-stop

  ##############################################################################
  defp format_error(err, tr), do: %{display: format_display_error(err, tr), trace: tr, error: err}

  # inner engram workings error; no line number
  defp format_display_error(error, nil) when is_binary(error), do: error

  # "rescued" :error from the eval of the engram
  defp format_display_error({:catch, :error, reason}, trace),
    do: Exception.normalize(:error, reason, trace) |> error_with_line(trace)

  # beam throw / exit
  defp format_display_error({:catch, kind, reason}, trace),
    do: error_with_line_("#{kind}: #{format_catch_reason(kind, reason)}", error_line(nil, trace))

  # # # # # # # # # #
  defp error_with_line(error, trace),
    do: error_with_line_(error_message(error), error_line(error, trace))

  # # # # # # # # # #
  # this first condition is a hard scenario to test, but in theory it might
  # still happen, so just keep it for now as a defense posture
  # coveralls-ignore-next-line
  defp error_with_line_(message, nil), do: message
  defp error_with_line_(message, line), do: "Line #{line}: #{message}"

  # # # # # # # # # #
  defp format_catch_reason(_, reason) when is_binary(reason), do: reason
  defp format_catch_reason(:exit, reason), do: Exception.format_exit(reason)
  defp format_catch_reason(:throw, reason), do: inspect(reason)

  # # # # # # # # # #
  defp error_line(%{line: line}, _) when is_integer(line) and line > 0, do: line

  defp error_line(_, trace) when is_list(trace) do
    Enum.find_value(trace, fn
      {_module, _function, _arity, location} -> Keyword.get(location, :line)
      # this is defensive. I can't figure out a scenario to test it, but it is
      # part of the documented trace format, so...
      # coveralls-ignore-next-line
      {_fun, _arity, location} -> Keyword.get(location, :line)
    end)
  end

  # # # # # # # # # #
  defp error_message(%EEx.SyntaxError{message: message}), do: message
  defp error_message(%{description: description}) when is_binary(description), do: description
  defp error_message(error) when is_map(error), do: Exception.message(error)
end
