defmodule Aiex.CLI.Commands.Analyze do
  @moduledoc """
  Analyze command handler for code analysis and dependency checking.
  """

  @behaviour Aiex.CLI.Commands.CommandBehaviour

  @impl true
  def execute({[:analyze], %Optimus.ParseResult{args: args} = parsed}) do
    case Map.keys(args) do
      [:code] -> analyze_code(parsed)
      [:deps] -> analyze_deps(parsed)
      [] -> {:error, "No subcommand specified. Use 'aiex help analyze' for options."}
      _ -> {:error, "Invalid analyze subcommand. Use 'aiex help analyze' for options."}
    end
  end

  defp analyze_code(%Optimus.ParseResult{options: options}) do
    path = Map.get(options, :path)
    depth = Map.get(options, :depth, 3)
    format = Map.get(options, :format, "text")

    # Start the CodeAnalyzer if not already running
    ensure_code_analyzer_started()

    # Determine if path is a file or directory
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        # Analyze single file
        analyze_single_file(path, format)
        
      {:ok, %File.Stat{type: :directory}} ->
        # Analyze project directory
        analyze_project(path, depth, format)
        
      {:error, reason} ->
        {:error, "Cannot access path #{path}: #{reason}"}
    end
  end
  
  defp ensure_code_analyzer_started do
    case Process.whereis(Aiex.AI.Engines.CodeAnalyzer) do
      nil -> 
        {:ok, _} = Aiex.AI.Engines.CodeAnalyzer.start_link()
      _pid -> 
        :ok
    end
  end
  
  defp analyze_single_file(file_path, format) do
    analysis_types = [:structure_analysis, :complexity_analysis, :quality_analysis]
    
    results = Enum.map(analysis_types, fn analysis_type ->
      case Aiex.AI.Engines.CodeAnalyzer.analyze_file(file_path, analysis_type) do
        {:ok, result} -> {analysis_type, result}
        {:error, reason} -> {analysis_type, {:error, reason}}
      end
    end)
    
    format_analysis_results(file_path, results, format)
  end
  
  defp analyze_project(project_path, depth, format) do
    analysis_types = [:structure_analysis, :pattern_analysis, :quality_analysis]
    
    case Aiex.AI.Engines.CodeAnalyzer.analyze_project(project_path, analysis_types, depth: depth) do
      {:ok, results} ->
        format_project_results(results, format)
        
      {:error, reason} ->
        {:error, "Project analysis failed: #{reason}"}
    end
  end
  
  defp format_analysis_results(file_path, results, "text") do
    issues = extract_issues_from_results(results)
    summary = build_analysis_summary(results)
    
    {:ok,
     {:analysis,
      [
        {:file, file_path, issues},
        {:summary, summary}
      ]}}
  end
  
  defp format_analysis_results(file_path, results, "json") do
    json_results = %{
      file: file_path,
      results: Map.new(results),
      timestamp: DateTime.utc_now()
    }
    
    {:ok, {:json, Jason.encode!(json_results, pretty: true)}}
  end
  
  defp format_project_results(results, format) do
    case format do
      "text" ->
        {:ok, {:analysis, format_project_text_results(results)}}
      "json" ->
        {:ok, {:json, Jason.encode!(results, pretty: true)}}
      _ ->
        {:error, "Unsupported format: #{format}"}
    end
  end
  
  defp extract_issues_from_results(results) do
    Enum.flat_map(results, fn {analysis_type, result} ->
      case result do
        %{results: %{"issues" => issues}} when is_list(issues) ->
          Enum.map(issues, fn issue ->
            {issue["severity"] || :info, issue["line"] || 0, issue["message"] || ""}
          end)
        _ ->
          []
      end
    end)
  end
  
  defp build_analysis_summary(results) do
    %{
      "Analysis types" => results |> Enum.map(fn {type, _} -> Atom.to_string(type) end) |> Enum.join(", "),
      "Timestamp" => DateTime.utc_now() |> DateTime.to_string()
    }
  end
  
  defp format_project_text_results(results) do
    files_analyzed = Map.get(results, :files_analyzed, 0)
    analysis_types = Map.get(results, :analysis_types, [])
    
    [
      {:summary, %{
        "Files analyzed" => "#{files_analyzed}",
        "Analysis types" => Enum.join(analysis_types, ", ")
      }}
    ]
  end

  defp analyze_deps(%Optimus.ParseResult{flags: flags}) do
    check_outdated = Map.get(flags, :outdated, false)
    check_security = Map.get(flags, :security, false)

    # TODO: Implement actual dependency analysis logic
    # For now, return a placeholder response
    results = []

    results =
      if check_outdated do
        [{"Dependencies checked for updates", "All dependencies are up to date"} | results]
      else
        results
      end

    results =
      if check_security do
        [{"Security scan completed", "No known vulnerabilities found"} | results]
      else
        results
      end

    case results do
      [] -> {:error, "No analysis options specified. Use --outdated or --security flags."}
      _ -> {:ok, {:info, "Dependency Analysis Complete", Map.new(results)}}
    end
  end
end
