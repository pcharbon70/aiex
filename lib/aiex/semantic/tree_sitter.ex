defmodule Aiex.Semantic.TreeSitter do
  @moduledoc """
  Tree-sitter integration via Rustler NIFs for semantic code parsing.

  This module provides fast, accurate parsing of Elixir code using Tree-sitter
  grammars. Falls back gracefully when Rustler is not available.
  """

  # This will be implemented as a Rustler NIF
  # For now, we'll use a fallback implementation

  @doc """
  Parses Elixir code and returns an AST with semantic information.
  """
  def parse_elixir(code) when is_binary(code) do
    if rustler_available?() do
      # TODO: Call Rustler NIF
      parse_elixir_nif(code)
    else
      # Fallback to Code.string_to_quoted
      parse_elixir_fallback(code)
    end
  end

  @doc """
  Extracts semantic chunks from parsed AST.
  """
  def extract_chunks(ast, opts \\ []) do
    max_size = Keyword.get(opts, :max_size, 2000)

    ast
    |> flatten_ast()
    |> group_by_semantic_units()
    |> split_by_size(max_size)
  end

  @doc """
  Gets the byte range for a specific AST node.
  """
  def get_node_range(node) do
    # TODO: Implement when NIF is ready
    {:ok, {0, 0}}
  end

  ## Private Functions (Fallback Implementation)

  defp parse_elixir_nif(code) do
    # This will be the actual NIF call
    # For now, return error to trigger fallback
    {:error, :nif_not_implemented}
  end

  defp parse_elixir_fallback(code) do
    try do
      case Code.string_to_quoted(code, columns: true) do
        {:ok, ast} ->
          {:ok, wrap_ast_with_metadata(ast, code)}

        {:error, _} = error ->
          error
      end
    rescue
      e ->
        {:error, {:parse_error, e}}
    end
  end

  defp wrap_ast_with_metadata(ast, code) do
    lines = String.split(code, "\n")

    # Add line and position metadata to AST nodes
    Macro.prewalk(ast, fn
      {form, meta, args} ->
        enhanced_meta =
          Keyword.merge(meta,
            source_code: code,
            total_lines: length(lines)
          )

        {form, enhanced_meta, args}

      other ->
        other
    end)
  end

  defp flatten_ast(ast) do
    # Convert AST to flat list of semantic units
    ast
    |> Macro.prewalk([], fn
      {:defmodule, meta, [name | body]} = node, acc ->
        unit = %{
          type: :module,
          name: module_name(name),
          line: Keyword.get(meta, :line),
          node: node,
          size: estimate_node_size(node)
        }

        {node, [unit | acc]}

      {:def, meta, [{name, _, _} | _]} = node, acc ->
        unit = %{
          type: :function,
          name: name,
          line: Keyword.get(meta, :line),
          node: node,
          size: estimate_node_size(node)
        }

        {node, [unit | acc]}

      {:defp, meta, [{name, _, _} | _]} = node, acc ->
        unit = %{
          type: :private_function,
          name: name,
          line: Keyword.get(meta, :line),
          node: node,
          size: estimate_node_size(node)
        }

        {node, [unit | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp group_by_semantic_units(units) do
    # Group related units together
    units
    |> Enum.chunk_by(fn unit ->
      case unit.type do
        :module -> {:module, unit.name}
        _ -> :function_group
      end
    end)
  end

  defp split_by_size(groups, max_size) do
    Enum.flat_map(groups, fn group ->
      total_size = Enum.sum(Enum.map(group, & &1.size))

      if total_size <= max_size do
        [create_chunk(group)]
      else
        split_large_group(group, max_size)
      end
    end)
  end

  defp split_large_group(group, max_size) do
    group
    |> Enum.reduce({[], [], 0}, fn unit, {chunks, current, size} ->
      unit_size = unit.size

      if size + unit_size <= max_size do
        {chunks, [unit | current], size + unit_size}
      else
        new_chunk = create_chunk(Enum.reverse(current))
        {[new_chunk | chunks], [unit], unit_size}
      end
    end)
    |> case do
      {chunks, [], _} -> Enum.reverse(chunks)
      {chunks, current, _} -> Enum.reverse([create_chunk(Enum.reverse(current)) | chunks])
    end
  end

  defp create_chunk(units) do
    %{
      units: units,
      type: :semantic_chunk,
      start_line: units |> Enum.map(& &1.line) |> Enum.min(),
      end_line: units |> Enum.map(& &1.line) |> Enum.max(),
      size: Enum.sum(Enum.map(units, & &1.size)),
      content: units_to_code(units)
    }
  end

  defp units_to_code(units) do
    # Convert units back to source code
    units
    |> Enum.map(fn unit ->
      unit.node |> Macro.to_string()
    end)
    |> Enum.join("\n\n")
  end

  defp module_name({:__aliases__, _, aliases}) do
    aliases |> Enum.join(".")
  end

  defp module_name(name) when is_atom(name), do: Atom.to_string(name)
  defp module_name(other), do: inspect(other)

  defp estimate_node_size(node) do
    # Rough estimation of tokens in a node
    node
    |> Macro.to_string()
    |> String.split(~r/\s+/)
    |> length()
  end

  defp rustler_available? do
    # Check if Rustler is compiled and available
    Application.loaded_applications()
    |> Enum.any?(fn {app, _, _} -> app == :rustler end)
  end
end
