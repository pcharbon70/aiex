defmodule Aiex.CLI.Commands.AI.OutputFormatter do
  @moduledoc """
  Output formatting utilities for AI command results.
  
  Provides consistent formatting for different types of AI responses
  across various output formats (text, JSON, markdown).
  """
  
  @doc """
  Format AI analysis results for display.
  """
  def format_analysis_result(response, format \\ "text")
  
  def format_analysis_result(response, "json") do
    response
    |> extract_analysis_data()
    |> Jason.encode!(pretty: true)
  end
  
  def format_analysis_result(response, "markdown") do
    data = extract_analysis_data(response)
    
    """
    # Code Analysis Results
    
    ## Summary
    #{data.summary || "No summary available"}
    
    ## Quality Score
    **#{data.quality_score || "N/A"}/10**
    
    ## Issues Found
    #{format_issues_markdown(data.issues)}
    
    ## Recommendations
    #{format_recommendations_markdown(data.recommendations)}
    
    ## Detailed Insights
    #{data.insights || "No detailed insights available"}
    """
  end
  
  def format_analysis_result(response, "text") do
    data = extract_analysis_data(response)
    
    """
    📊 Code Analysis Results
    #{String.duplicate("=", 50)}
    
    Summary: #{data.summary || "No summary available"}
    Quality Score: #{data.quality_score || "N/A"}/10
    
    #{format_issues_text(data.issues)}
    
    #{format_recommendations_text(data.recommendations)}
    
    💡 Insights:
    #{data.insights || "No detailed insights available"}
    """
  end
  
  @doc """
  Format AI code generation results.
  """
  def format_generation_result(response, generation_type) do
    data = extract_generation_data(response)
    
    """
    🚀 Generated #{String.capitalize(to_string(generation_type))}
    #{String.duplicate("=", 50)}
    
    #{data.description || "Generated code"}
    
    ```elixir
    #{data.code || "# No code generated"}
    ```
    
    💡 Implementation Notes:
    #{format_implementation_notes(data.notes)}
    
    🔧 Usage Instructions:
    #{data.usage || "No specific usage instructions provided"}
    """
  end
  
  @doc """
  Format AI explanation results.
  """
  def format_explanation_result(response, level, focus) do
    data = extract_explanation_data(response)
    
    """
    📖 Code Explanation (#{level} level, #{focus} focus)
    #{String.duplicate("=", 60)}
    
    ## Overview
    #{data.overview || "No overview available"}
    
    ## Key Concepts
    #{format_concepts_list(data.concepts)}
    
    ## Code Structure
    #{data.structure || "No structure analysis available"}
    
    ## Implementation Details
    #{data.details || "No implementation details available"}
    
    #{if level == "advanced", do: format_advanced_explanation(data), else: ""}
    
    ## Best Practices
    #{format_best_practices(data.best_practices)}
    """
  end
  
  @doc """
  Format AI refactoring results.
  """
  def format_refactor_result(response, refactor_type, show_preview \\ false) do
    data = extract_refactor_data(response)
    
    base_output = """
    🔧 Refactoring Analysis (#{refactor_type})
    #{String.duplicate("=", 50)}
    
    ## Summary
    #{data.summary || "No summary available"}
    
    ## Suggested Changes
    #{format_refactor_suggestions(data.suggestions)}
    
    ## Impact Assessment
    #{format_impact_assessment(data.impact)}
    """
    
    if show_preview and data.preview_code do
      base_output <> """
      
      ## Preview of Refactored Code
      #{String.duplicate("-", 40)}
      
      ```elixir
      #{data.preview_code}
      ```
      
      To apply these changes, run with --apply flag.
      """
    else
      base_output
    end
  end
  
  @doc """
  Format AI workflow execution results.
  """
  def format_workflow_result(workflow_state, template) do
    """
    🔄 Workflow Execution: #{template}
    #{String.duplicate("=", 50)}
    
    Status: #{workflow_state.status || "Unknown"}
    Steps Completed: #{length(workflow_state.completed_steps || [])}
    Duration: #{format_duration(workflow_state.duration_ms)}
    
    ## Execution Summary
    #{workflow_state.summary || "No summary available"}
    
    ## Step Results
    #{format_workflow_steps(workflow_state.completed_steps || [])}
    
    ## Final Output
    #{workflow_state.final_output || "No final output generated"}
    """
  end
  
  @doc """
  Format chat session information.
  """
  def format_chat_info(conversation_id, type, context) do
    """
    💬 AI Chat Session
    #{String.duplicate("=", 30)}
    
    Conversation ID: #{conversation_id}
    Type: #{type}
    Context: #{context}
    Started: #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")}
    
    Use 'aiex shell --mode chat' to continue this conversation.
    """
  end
  
  # Private helper functions for data extraction
  
  defp extract_analysis_data(response) do
    %{
      summary: get_nested(response, [:summary]) || get_nested(response, [:result, :summary]),
      quality_score: get_nested(response, [:quality_score]) || get_nested(response, [:result, :quality_score]),
      issues: get_nested(response, [:issues]) || get_nested(response, [:result, :issues]) || [],
      recommendations: get_nested(response, [:recommendations]) || get_nested(response, [:result, :recommendations]) || [],
      insights: get_nested(response, [:insights]) || get_nested(response, [:result, :insights])
    }
  end
  
  defp extract_generation_data(response) do
    %{
      description: get_nested(response, [:description]) || get_nested(response, [:result, :description]),
      code: get_nested(response, [:artifacts, :code]) || get_nested(response, [:result, :code]),
      notes: get_nested(response, [:notes]) || get_nested(response, [:result, :notes]) || [],
      usage: get_nested(response, [:usage]) || get_nested(response, [:result, :usage])
    }
  end
  
  defp extract_explanation_data(response) do
    %{
      overview: get_nested(response, [:overview]) || get_nested(response, [:result, :overview]),
      concepts: get_nested(response, [:concepts]) || get_nested(response, [:result, :concepts]) || [],
      structure: get_nested(response, [:structure]) || get_nested(response, [:result, :structure]),
      details: get_nested(response, [:details]) || get_nested(response, [:result, :details]),
      best_practices: get_nested(response, [:best_practices]) || get_nested(response, [:result, :best_practices]) || []
    }
  end
  
  defp extract_refactor_data(response) do
    %{
      summary: get_nested(response, [:summary]) || get_nested(response, [:result, :summary]),
      suggestions: get_nested(response, [:suggestions]) || get_nested(response, [:result, :suggestions]) || [],
      impact: get_nested(response, [:impact]) || get_nested(response, [:result, :impact]),
      preview_code: get_nested(response, [:artifacts, :code]) || get_nested(response, [:result, :refactored_code])
    }
  end
  
  defp get_nested(map, keys) when is_map(map) do
    Enum.reduce(keys, map, fn key, acc ->
      if is_map(acc), do: Map.get(acc, key), else: nil
    end)
  end
  defp get_nested(_, _), do: nil
  
  # Formatting helper functions
  
  defp format_issues_markdown([]), do: "No issues found."
  defp format_issues_markdown(issues) do
    issues
    |> Enum.map(fn issue ->
      severity = Map.get(issue, :severity, "info")
      message = Map.get(issue, :message, "Unknown issue")
      "- **#{String.upcase(severity)}**: #{message}"
    end)
    |> Enum.join("\n")
  end
  
  defp format_issues_text([]), do: "✅ No issues found."
  defp format_issues_text(issues) do
    header = "⚠️  Issues Found (#{length(issues)}):\n"
    
    issue_list = issues
    |> Enum.with_index(1)
    |> Enum.map(fn {issue, index} ->
      severity = Map.get(issue, :severity, "info")
      message = Map.get(issue, :message, "Unknown issue")
      severity_icon = case severity do
        "error" -> "❌"
        "warning" -> "⚠️"
        "info" -> "ℹ️"
        _ -> "•"
      end
      "   #{index}. #{severity_icon} #{message}"
    end)
    |> Enum.join("\n")
    
    header <> issue_list
  end
  
  defp format_recommendations_markdown([]), do: "No specific recommendations."
  defp format_recommendations_markdown(recommendations) do
    recommendations
    |> Enum.map(fn rec ->
      title = Map.get(rec, :title, "Recommendation")
      description = Map.get(rec, :description, "No description")
      "- **#{title}**: #{description}"
    end)
    |> Enum.join("\n")
  end
  
  defp format_recommendations_text([]), do: "💡 No specific recommendations."
  defp format_recommendations_text(recommendations) do
    header = "🔧 Recommendations (#{length(recommendations)}):\n"
    
    rec_list = recommendations
    |> Enum.with_index(1)
    |> Enum.map(fn {rec, index} ->
      title = Map.get(rec, :title, "Recommendation")
      description = Map.get(rec, :description, "No description")
      "   #{index}. #{title}: #{description}"
    end)
    |> Enum.join("\n")
    
    header <> rec_list
  end
  
  defp format_concepts_list([]), do: "No key concepts identified."
  defp format_concepts_list(concepts) do
    concepts
    |> Enum.map(fn concept ->
      name = Map.get(concept, :name, "Unknown")
      description = Map.get(concept, :description, "No description")
      "• **#{name}**: #{description}"
    end)
    |> Enum.join("\n")
  end
  
  defp format_implementation_notes([]), do: "No specific implementation notes."
  defp format_implementation_notes(notes) do
    notes
    |> Enum.map(fn note -> "• #{note}" end)
    |> Enum.join("\n")
  end
  
  defp format_best_practices([]), do: "No specific best practices identified."
  defp format_best_practices(practices) do
    practices
    |> Enum.map(fn practice -> "• #{practice}" end)
    |> Enum.join("\n")
  end
  
  defp format_advanced_explanation(data) do
    case Map.get(data, :advanced_topics) do
      nil -> ""
      topics ->
        """
        
        ## Advanced Topics
        #{format_advanced_topics(topics)}
        """
    end
  end
  
  defp format_advanced_topics(topics) when is_list(topics) do
    topics
    |> Enum.map(fn topic ->
      title = Map.get(topic, :title, "Advanced Topic")
      content = Map.get(topic, :content, "No content")
      "### #{title}\n#{content}"
    end)
    |> Enum.join("\n\n")
  end
  defp format_advanced_topics(_), do: "No advanced topics available."
  
  defp format_refactor_suggestions([]), do: "No refactoring suggestions."
  defp format_refactor_suggestions(suggestions) do
    suggestions
    |> Enum.with_index(1)
    |> Enum.map(fn {suggestion, index} ->
      title = Map.get(suggestion, :title, "Refactoring")
      description = Map.get(suggestion, :description, "No description")
      impact = Map.get(suggestion, :impact, "unknown")
      "   #{index}. #{title} (Impact: #{impact})\n      #{description}"
    end)
    |> Enum.join("\n")
  end
  
  defp format_impact_assessment(nil), do: "No impact assessment available."
  defp format_impact_assessment(impact) do
    """
    Risk Level: #{Map.get(impact, :risk, "unknown")}
    Estimated Effort: #{Map.get(impact, :effort, "unknown")}
    Benefits: #{Map.get(impact, :benefits, "Not specified")}
    """
  end
  
  defp format_workflow_steps([]), do: "No steps completed."
  defp format_workflow_steps(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, index} ->
      name = Map.get(step, :name, "Step #{index}")
      status = Map.get(step, :status, "unknown")
      duration = Map.get(step, :duration_ms, 0)
      status_icon = if status == "completed", do: "✅", else: "❌"
      "   #{index}. #{status_icon} #{name} (#{format_duration(duration)})"
    end)
    |> Enum.join("\n")
  end
  
  defp format_duration(nil), do: "0ms"
  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> 
        minutes = div(ms, 60_000)
        seconds = div(rem(ms, 60_000), 1000)
        "#{minutes}m #{seconds}s"
    end
  end
  defp format_duration(_), do: "unknown"
end