defmodule Aiex.CLI.Commands.AI.OutputFormatter do
  @moduledoc """

  Output formatting utilities for AI command responses.
  
  Provides consistent formatting for different types of AI outputs including
  code analysis, explanations, refactoring suggestions, and workflow results.
  """

  @doc """
  Format AI analysis results for display.
  """
  def format_analysis(response, format \\ "text")

  def format_analysis(response, "text") do
    """
    📊 AI Code Analysis Results
    #{String.duplicate("=", 50)}

    #{format_analysis_summary(response)}

    #{format_analysis_details(response)}

    #{format_recommendations(response)}
    """
  end

  def format_analysis(response, "json") do
    Jason.encode!(response, pretty: true)
  end

  def format_analysis(response, "markdown") do
    """
    # 📊 AI Code Analysis Results

    ## Summary
    #{format_analysis_summary(response)}

    ## Detailed Analysis
    #{format_analysis_details(response)}

    ## Recommendations
    #{format_recommendations(response)}
    """
  end

  @doc """
  Format AI code explanation for display.
  """
  def format_explanation(response) do
    """
    🤖 AI Code Explanation
    #{String.duplicate("=", 50)}

    #{format_explanation_overview(response)}

    #{format_code_structure(response)}

    #{format_key_concepts(response)}

    #{format_complexity_analysis(response)}
    """
  end

  @doc """
  Format refactoring suggestions for preview.
  """
  def format_refactoring_preview(response) do
    """
    🔄 Refactoring Preview
    #{String.duplicate("=", 50)}

    #{format_refactoring_summary(response)}

    #{format_changes_preview(response)}

    #{format_impact_analysis(response)}

    💡 Use --apply to apply these changes or --preview=false to see suggestions only.
    """
  end

  @doc """
  Format refactoring suggestions without preview.
  """
  def format_refactoring_suggestions(response) do
    """
    🔄 Refactoring Suggestions
    #{String.duplicate("=", 50)}

    #{format_refactoring_summary(response)}

    #{format_suggestions_list(response)}

    #{format_next_steps(response)}
    """
  end

  @doc """
  Format workflow execution results.
  """
  def format_workflow_results(workflow_state) do
    """
    🔧 Workflow Execution Results
    #{String.duplicate("=", 50)}

    Status: #{format_workflow_status(workflow_state.status)}
    Duration: #{format_duration(workflow_state.duration_ms)}
    Steps Completed: #{length(workflow_state.completed_steps)}/#{length(workflow_state.all_steps)}

    #{format_workflow_steps(workflow_state)}

    #{format_workflow_artifacts(workflow_state)}
    """
  end

  # Private formatting functions

  defp format_analysis_summary(response) do
    case Map.get(response, :summary) do
      nil -> "No summary available."
      summary -> 
        """
        Overall Assessment: #{Map.get(summary, :overall_score, "N/A")}/10
        Code Quality: #{Map.get(summary, :quality_score, "N/A")}/10
        Maintainability: #{Map.get(summary, :maintainability_score, "N/A")}/10
        Performance: #{Map.get(summary, :performance_score, "N/A")}/10
        
        #{Map.get(summary, :description, "")}
        """
    end
  end

  defp format_analysis_details(response) do
    case Map.get(response, :details) do
      nil -> ""
      details ->
        sections = for {category, items} <- details do
          """
          #{String.capitalize(to_string(category))}:
          #{format_detail_items(items)}
          """
        end
        Enum.join(sections, "\n")
    end
  end

  defp format_detail_items(items) when is_list(items) do
    items
    |> Enum.map(fn item ->
      case item do
        %{severity: severity, message: message, line: line} ->
          "  • [#{severity}] Line #{line}: #{message}"
        %{message: message} ->
          "  • #{message}"
        item when is_binary(item) ->
          "  • #{item}"
        _ ->
          "  • #{inspect(item)}"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_detail_items(items), do: "  • #{inspect(items)}"

  defp format_recommendations(response) do
    case Map.get(response, :recommendations) do
      nil -> ""
      recommendations when is_list(recommendations) ->
        """
        💡 Recommendations:
        #{format_recommendation_list(recommendations)}
        """
      recommendations ->
        "💡 Recommendations: #{recommendations}"
    end
  end

  defp format_recommendation_list(recommendations) do
    recommendations
    |> Enum.with_index(1)
    |> Enum.map(fn {rec, index} ->
      case rec do
        %{priority: priority, action: action, description: description} ->
          "#{index}. [#{priority}] #{action}\n   #{description}"
        %{action: action, description: description} ->
          "#{index}. #{action}\n   #{description}"
        rec when is_binary(rec) ->
          "#{index}. #{rec}"
        _ ->
          "#{index}. #{inspect(rec)}"
      end
    end)
    |> Enum.join("\n\n")
  end

  defp format_explanation_overview(response) do
    case Map.get(response, :overview) do
      nil -> "No overview available."
      overview ->
        """
        Purpose: #{Map.get(overview, :purpose, "Not specified")}
        Language: #{Map.get(overview, :language, "Unknown")}
        Complexity: #{Map.get(overview, :complexity_level, "Unknown")}
        
        #{Map.get(overview, :description, "")}
        """
    end
  end

  defp format_code_structure(response) do
    case Map.get(response, :structure) do
      nil -> ""
      structure ->
        """
        📁 Code Structure:
        #{format_structure_items(structure)}
        """
    end
  end

  defp format_structure_items(structure) when is_map(structure) do
    for {category, items} <- structure do
      """
      #{String.capitalize(to_string(category))}:
      #{format_structure_list(items)}
      """
    end
    |> Enum.join("\n")
  end

  defp format_structure_items(structure), do: inspect(structure)

  defp format_structure_list(items) when is_list(items) do
    items
    |> Enum.map(fn item ->
      case item do
        %{name: name, line: line, description: desc} ->
          "  • #{name} (line #{line}): #{desc}"
        %{name: name, description: desc} ->
          "  • #{name}: #{desc}"
        %{name: name} ->
          "  • #{name}"
        item when is_binary(item) ->
          "  • #{item}"
        _ ->
          "  • #{inspect(item)}"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_structure_list(items), do: "  • #{inspect(items)}"

  defp format_key_concepts(response) do
    case Map.get(response, :key_concepts) do
      nil -> ""
      concepts when is_list(concepts) ->
        """
        🔑 Key Concepts:
        #{format_concept_list(concepts)}
        """
      concepts ->
        "🔑 Key Concepts: #{concepts}"
    end
  end

  defp format_concept_list(concepts) do
    concepts
    |> Enum.map(fn concept ->
      case concept do
        %{term: term, explanation: explanation} ->
          "  • #{term}: #{explanation}"
        concept when is_binary(concept) ->
          "  • #{concept}"
        _ ->
          "  • #{inspect(concept)}"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_complexity_analysis(response) do
    case Map.get(response, :complexity) do
      nil -> ""
      complexity ->
        """
        📈 Complexity Analysis:
        Cyclomatic Complexity: #{Map.get(complexity, :cyclomatic, "N/A")}
        Cognitive Complexity: #{Map.get(complexity, :cognitive, "N/A")}
        Lines of Code: #{Map.get(complexity, :loc, "N/A")}
        
        #{Map.get(complexity, :assessment, "")}
        """
    end
  end

  defp format_refactoring_summary(response) do
    case Map.get(response, :summary) do
      nil -> "No refactoring summary available."
      summary ->
        """
        Refactoring Type: #{Map.get(summary, :type, "General")}
        Estimated Impact: #{Map.get(summary, :impact_level, "Unknown")}
        Changes Proposed: #{Map.get(summary, :changes_count, 0)}
        
        #{Map.get(summary, :description, "")}
        """
    end
  end

  defp format_changes_preview(response) do
    case Map.get(response, :changes_preview) do
      nil -> ""
      preview ->
        """
        📝 Changes Preview:
        #{preview}
        """
    end
  end

  defp format_impact_analysis(response) do
    case Map.get(response, :impact_analysis) do
      nil -> ""
      impact ->
        """
        📊 Impact Analysis:
        Breaking Changes: #{if Map.get(impact, :has_breaking_changes), do: "Yes", else: "No"}
        Test Updates Required: #{if Map.get(impact, :requires_test_updates), do: "Yes", else: "No"}
        Dependencies Affected: #{Map.get(impact, :dependencies_affected, 0)}
        
        #{Map.get(impact, :notes, "")}
        """
    end
  end

  defp format_suggestions_list(response) do
    case Map.get(response, :suggestions) do
      nil -> "No suggestions available."
      suggestions when is_list(suggestions) ->
        suggestions
        |> Enum.with_index(1)
        |> Enum.map(fn {suggestion, index} ->
          case suggestion do
            %{title: title, description: description, difficulty: difficulty} ->
              "#{index}. #{title} [#{difficulty}]\n   #{description}"
            %{title: title, description: description} ->
              "#{index}. #{title}\n   #{description}"
            suggestion when is_binary(suggestion) ->
              "#{index}. #{suggestion}"
            _ ->
              "#{index}. #{inspect(suggestion)}"
          end
        end)
        |> Enum.join("\n\n")
      suggestions ->
        inspect(suggestions)
    end
  end

  defp format_next_steps(response) do
    case Map.get(response, :next_steps) do
      nil -> ""
      steps when is_list(steps) ->
        """
        
        🎯 Recommended Next Steps:
        #{Enum.with_index(steps, 1) |> Enum.map(fn {step, i} -> "#{i}. #{step}" end) |> Enum.join("\n")}
        """
      steps ->
        "\n🎯 Next Steps: #{steps}"
    end
  end

  defp format_workflow_status(:completed), do: "✅ Completed"
  defp format_workflow_status(:failed), do: "❌ Failed"
  defp format_workflow_status(:running), do: "🔄 Running"
  defp format_workflow_status(:pending), do: "⏳ Pending"
  defp format_workflow_status(status), do: "#{status}"

  defp format_duration(nil), do: "N/A"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000 do
    seconds = div(ms, 1000)
    "#{seconds}s"
  end
  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1000)
    "#{minutes}m #{seconds}s"
  end

  defp format_workflow_steps(workflow_state) do
    case Map.get(workflow_state, :completed_steps) do
      nil -> ""
      completed_steps ->
        """
        
        📋 Completed Steps:
        #{format_step_list(completed_steps)}
        """
    end
  end

  defp format_step_list(steps) when is_list(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, index} ->
      case step do
        %{name: name, status: status, duration_ms: duration} ->
          "#{index}. #{name} - #{format_workflow_status(status)} (#{format_duration(duration)})"
        %{name: name, status: status} ->
          "#{index}. #{name} - #{format_workflow_status(status)}"
        %{name: name} ->
          "#{index}. #{name}"
        step when is_binary(step) ->
          "#{index}. #{step}"
        _ ->
          "#{index}. #{inspect(step)}"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_step_list(steps), do: inspect(steps)

  defp format_workflow_artifacts(workflow_state) do
    case Map.get(workflow_state, :artifacts) do
      nil -> ""
      artifacts when map_size(artifacts) == 0 -> ""
      artifacts ->
        """
        
        📦 Generated Artifacts:
        #{format_artifact_list(artifacts)}
        """
    end
  end

  defp format_artifact_list(artifacts) when is_map(artifacts) do
    for {type, items} <- artifacts do
      """
      #{String.capitalize(to_string(type))}:
      #{format_artifact_items(items)}
      """
    end
    |> Enum.join("\n")
  end

  defp format_artifact_items(items) when is_list(items) do
    items
    |> Enum.map(fn item ->
      case item do
        %{path: path, size: size} ->
          "  • #{path} (#{format_file_size(size)})"
        %{path: path} ->
          "  • #{path}"
        item when is_binary(item) ->
          "  • #{item}"
        _ ->
          "  • #{inspect(item)}"
      end
    end)
    |> Enum.join("\n")
  end

  defp format_artifact_items(items), do: "  • #{inspect(items)}"

  defp format_file_size(size) when size < 1024, do: "#{size} bytes"
  defp format_file_size(size) when size < 1024 * 1024 do
    kb = Float.round(size / 1024, 1)
    "#{kb} KB"
  end
  defp format_file_size(size) do
    mb = Float.round(size / (1024 * 1024), 1)
    "#{mb} MB"
  end
  
end