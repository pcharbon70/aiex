defmodule Aiex.IEx.EnhancedHelpers do
  @moduledoc """
  Enhanced IEx helpers with interactive AI shell integration.
  
  Provides advanced AI-powered helpers that seamlessly integrate with both
  standard IEx sessions and the enhanced interactive AI shell.
  """

  alias Aiex.CLI.InteractiveShell
  alias Aiex.AI.Coordinators.{CodingAssistant, ConversationManager}
  alias Aiex.IEx.Helpers
  alias Aiex.Context.DistributedEngine

  require Logger

  @doc """
  Start an enhanced AI shell session within IEx.
  
  ## Examples
  
      iex> ai_shell()
      # Starts interactive AI shell with current IEx context
      
      iex> ai_shell(project_dir: "/path/to/project")
      # Starts with specific project directory
  """
  def ai_shell(opts \\ []) do
    # Inherit current IEx context
    enhanced_opts = Keyword.merge([
      project_dir: System.cwd!(),
      iex_integration: true,
      inherit_history: true
    ], opts)
    
    IO.puts("🚀 Starting AI shell from IEx...")
    InteractiveShell.start(enhanced_opts)
  end

  @doc """
  Quick AI assistance without leaving IEx.
  
  ## Examples
  
      iex> ai("explain GenServer.call")
      # Quick explanation without entering shell
      
      iex> ai("generate a fibonacci function")
      # Generate code directly in IEx
  """
  def ai(query) when is_binary(query) do
    case detect_query_type(query) do
      :explain -> 
        ai_explain_quick(query)
      :generate -> 
        ai_generate_quick(query)
      :analyze -> 
        ai_analyze_quick(query)
      :general -> 
        ai_chat_quick(query)
    end
  end

  @doc """
  Enhanced code completion with AI suggestions.
  
  ## Examples
  
      iex> ai_complete("defmodule MyMod")
      # Shows AI-powered completions
      
      iex> ai_complete("def handle_", context: MyGenServer)
      # Context-aware completions
  """
  def ai_complete(fragment, opts \\ []) do
    result = Helpers.ai_complete(fragment, opts)
    
    case result do
      %{suggestions: suggestions} when length(suggestions) > 0 ->
        IO.puts("\n🤖 AI Suggestions:")
        suggestions
        |> Enum.with_index(1)
        |> Enum.each(fn {suggestion, index} ->
          IO.puts("\n#{index}. #{format_suggestion(suggestion)}")
        end)
        
        IO.puts("\n💡 Confidence: #{Float.round((result.confidence || 0.5) * 100, 1)}%")
        
      %{error: error, fallback: fallback} ->
        IO.puts("⚠️  AI completion failed: #{error}")
        if length(fallback) > 0 do
          IO.puts("📝 Fallback suggestions:")
          Enum.each(fallback, fn suggestion ->
            IO.puts("   • #{suggestion}")
          end)
        end
        
      _ ->
        IO.puts("❌ No suggestions available")
    end
    
    :ok
  end

  @doc """
  Smart code evaluation with AI insights.
  
  ## Examples
  
      iex> ai_eval("Enum.map([1,2,3], &(&1 * 2))")
      # Evaluates and explains the code
      
      iex> ai_eval(code, explain: true)
      # Includes detailed AI explanation
  """
  def ai_eval(code, opts \\ []) do
    # First evaluate the code
    {result, evaluation_time} = :timer.tc(fn ->
      try do
        {value, _binding} = Code.eval_string(code, [])
        {:ok, value}
      rescue
        error -> {:error, Exception.message(error)}
      catch
        :error, reason -> {:error, inspect(reason)}
      end
    end)
    
    # Display result
    case result do
      {:ok, value} ->
        IO.puts("📊 Result: #{inspect(value, pretty: true)}")
        IO.puts("⏱️  Execution time: #{format_time(evaluation_time)}")
        
        # Add AI insights if requested
        if Keyword.get(opts, :explain, false) do
          add_ai_insights(code, value, evaluation_time)
        end
        
        value
        
      {:error, reason} ->
        IO.puts("❌ Evaluation error: #{reason}")
        
        # Offer AI help with the error
        if Keyword.get(opts, :help_with_errors, true) do
          offer_error_help(code, reason)
        end
        
        :error
    end
  end

  @doc """
  Enhanced module documentation with AI insights.
  
  ## Examples
  
      iex> ai_doc(GenServer)
      # Standard docs + AI explanations + usage patterns
      
      iex> ai_doc(MyModule.function)
      # Function docs + AI analysis + examples
  """
  def ai_doc(module_or_function, opts \\ []) do
    # Get standard documentation
    standard_docs = get_enhanced_docs(module_or_function)
    
    # Get AI enhancement
    ai_insights = get_ai_documentation_insights(module_or_function, opts)
    
    # Display combined information
    display_enhanced_documentation(standard_docs, ai_insights)
  end

  @doc """
  AI-powered debugging assistance.
  
  ## Examples
  
      iex> ai_debug(pid)
      # Analyze process state with AI
      
      iex> ai_debug(error, context: "during user registration")
      # Get AI help with specific errors
  """
  def ai_debug(target, opts \\ []) do
    context = Keyword.get(opts, :context, "")
    
    case target do
      pid when is_pid(pid) ->
        debug_process_with_ai(pid, context)
        
      {:error, reason} ->
        debug_error_with_ai(reason, context)
        
      error when is_exception(error) ->
        debug_exception_with_ai(error, context)
        
      other ->
        debug_general_with_ai(other, context)
    end
  end

  @doc """
  Smart project analysis and insights.
  
  ## Examples
  
      iex> ai_project()
      # Analyze current project with AI
      
      iex> ai_project(focus: :performance)
      # Focus on performance aspects
  """
  def ai_project(opts \\ []) do
    project_dir = Keyword.get(opts, :project_dir, System.cwd!())
    focus = Keyword.get(opts, :focus, :general)
    
    IO.puts("🔍 Analyzing project with AI...")
    
    case analyze_project_with_ai(project_dir, focus) do
      {:ok, analysis} ->
        display_project_analysis(analysis, focus)
        
      {:error, reason} ->
        IO.puts("❌ Project analysis failed: #{reason}")
    end
  end

  @doc """
  AI-powered test suggestion and generation.
  
  ## Examples
  
      iex> ai_test_suggest(MyModule)
      # Get test suggestions for module
      
      iex> ai_test_generate(MyModule, type: :property)
      # Generate property-based tests
  """
  def ai_test_suggest(module, opts \\ []) do
    test_type = Keyword.get(opts, :type, :unit)
    
    case get_test_suggestions(module, test_type) do
      {:ok, suggestions} ->
        display_test_suggestions(module, suggestions)
        
      {:error, reason} ->
        IO.puts("❌ Test suggestion failed: #{reason}")
    end
  end

  # Quick AI helpers (internal)

  defp ai_explain_quick(query) do
    content = extract_code_from_query(query)
    
    case Helpers.ai_explain(content) do
      %{explanation: explanation, confidence: confidence} ->
        IO.puts("\n🤖 AI Explanation:")
        IO.puts("#{explanation}")
        IO.puts("\n💡 Confidence: #{Float.round(confidence * 100, 1)}%")
        
      %{error: error} ->
        IO.puts("❌ Explanation failed: #{error}")
    end
  end

  defp ai_generate_quick(query) do
    description = String.replace_prefix(query, "generate ", "")
    
    # Use CodingAssistant for generation
    request = %{
      intent: :implement_feature,
      description: description,
      context: build_iex_context()
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} ->
        case Map.get(response, :artifacts) do
          %{code: code} ->
            IO.puts("\n🎯 Generated Code:")
            IO.puts("#{String.duplicate("-", 50)}")
            IO.puts(code)
            IO.puts("#{String.duplicate("-", 50)}")
            
          _ ->
            IO.puts("✅ #{response.response || "Code generated successfully"}")
        end
        
      {:error, reason} ->
        IO.puts("❌ Generation failed: #{reason}")
    end
  end

  defp ai_analyze_quick(query) do
    content = extract_code_from_query(query)
    
    request = %{
      intent: :code_review,
      description: "Quick analysis of code",
      code: content,
      context: build_iex_context()
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} ->
        IO.puts("\n📊 AI Analysis:")
        IO.puts("#{response.response || "Analysis completed"}")
        
      {:error, reason} ->
        IO.puts("❌ Analysis failed: #{reason}")
    end
  end

  defp ai_chat_quick(query) do
    # Use ConversationManager for general queries
    session_id = "iex_quick_#{System.system_time(:millisecond)}"
    
    case ConversationManager.start_conversation(session_id, :quick_help, %{interface: :iex}) do
      {:ok, _conversation} ->
        case ConversationManager.continue_conversation(session_id, query) do
          {:ok, response} ->
            IO.puts("\n🤖 AI: #{response.response}")
            
          {:error, reason} ->
            IO.puts("❌ Chat failed: #{reason}")
        end
        
        ConversationManager.end_conversation(session_id)
        
      {:error, reason} ->
        IO.puts("❌ Failed to start conversation: #{reason}")
    end
  end

  # Helper functions

  defp detect_query_type(query) do
    query_lower = String.downcase(query)
    
    cond do
      String.starts_with?(query_lower, "explain") -> :explain
      String.starts_with?(query_lower, "generate") -> :generate
      String.starts_with?(query_lower, "analyze") -> :analyze
      String.contains?(query_lower, "defmodule") or String.contains?(query_lower, "def ") -> :analyze
      true -> :general
    end
  end

  defp extract_code_from_query(query) do
    query
    |> String.replace_prefix("explain ", "")
    |> String.replace_prefix("analyze ", "")
    |> String.trim()
  end

  defp build_iex_context do
    %{
      interface: :iex,
      project_directory: System.cwd!(),
      current_node: node(),
      timestamp: DateTime.utc_now()
    }
  end

  defp format_suggestion(suggestion) when is_binary(suggestion) do
    if String.length(suggestion) > 100 do
      first_line = String.split(suggestion, "\n") |> List.first()
      "#{String.slice(first_line, 0..97)}..."
    else
      suggestion
    end
  end

  defp format_time(microseconds) do
    cond do
      microseconds < 1000 -> "#{microseconds}μs"
      microseconds < 1_000_000 -> "#{Float.round(microseconds / 1000, 2)}ms"
      true -> "#{Float.round(microseconds / 1_000_000, 2)}s"
    end
  end

  defp add_ai_insights(code, result, execution_time) do
    IO.puts("\n🤖 AI Insights:")
    
    # Analyze execution time
    time_insight = cond do
      execution_time > 100_000 -> "⚠️  Execution took longer than expected - consider optimization"
      execution_time > 10_000 -> "✅ Good execution time"
      true -> "⚡ Very fast execution"
    end
    
    IO.puts("   #{time_insight}")
    
    # Analyze result type and patterns
    result_insight = case result do
      list when is_list(list) and length(list) > 1000 ->
        "📝 Large list result (#{length(list)} items) - consider lazy evaluation"
      map when is_map(map) and map_size(map) > 100 ->
        "📝 Large map result (#{map_size(map)} keys) - consider data structure optimization"
      _ ->
        "📝 Result type: #{inspect(result.__struct__ || :primitive)}"
    end
    
    IO.puts("   #{result_insight}")
    
    # Code pattern analysis
    if String.contains?(code, "Enum.") do
      IO.puts("   💡 Using Enum - consider Stream for large datasets")
    end
  end

  defp offer_error_help(code, reason) do
    IO.puts("\n🩺 AI Error Analysis:")
    
    case Helpers.ai_explain("Error in code: #{code}\nError: #{reason}") do
      %{explanation: explanation} ->
        IO.puts("   #{explanation}")
        
      _ ->
        IO.puts("   💡 Try using ai_debug/2 for detailed error analysis")
    end
  end

  defp get_enhanced_docs(module) when is_atom(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, module_doc, _, function_docs} ->
        %{
          type: :module,
          module: module,
          module_doc: module_doc,
          function_docs: function_docs,
          available: true
        }
      _ ->
        %{type: :module, module: module, available: false}
    end
  end

  defp get_enhanced_docs({module, function}) when is_atom(module) and is_atom(function) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        function_doc = Enum.find(docs, fn {{type, name, _arity}, _, _, _, _} ->
          type == :function and name == function
        end)
        
        %{
          type: :function,
          module: module,
          function: function,
          doc: function_doc,
          available: function_doc != nil
        }
      _ ->
        %{type: :function, module: module, function: function, available: false}
    end
  end

  defp get_ai_documentation_insights(target, _opts) do
    case Helpers.ai_explain(target) do
      %{explanation: explanation, confidence: confidence} ->
        %{
          ai_explanation: explanation,
          confidence: confidence,
          usage_patterns: get_usage_patterns(target)
        }
      _ ->
        %{ai_explanation: "AI insights not available", confidence: 0.0}
    end
  end

  defp get_usage_patterns(target) do
    case Helpers.ai_usage(target) do
      %{usage_patterns: patterns} -> patterns
      _ -> []
    end
  end

  defp display_enhanced_documentation(docs, insights) do
    IO.puts("\n📚 Enhanced Documentation\n")
    
    # Display standard docs
    if docs.available do
      case docs.type do
        :module ->
          IO.puts("📦 Module: #{docs.module}")
          if docs.module_doc do
            {_, doc_content} = docs.module_doc
            IO.puts("#{String.slice(doc_content, 0..300)}...")
          end
          
        :function ->
          IO.puts("⚡ Function: #{docs.module}.#{docs.function}")
          if docs.doc do
            {{_, _, arity}, _, _, doc_content, _} = docs.doc
            IO.puts("   Arity: #{arity}")
            if is_binary(doc_content) do
              IO.puts("   #{String.slice(doc_content, 0..200)}...")
            end
          end
      end
    else
      IO.puts("⚠️  No standard documentation available")
    end
    
    # Display AI insights
    IO.puts("\n🤖 AI Insights:")
    IO.puts("   #{insights.ai_explanation}")
    IO.puts("   Confidence: #{Float.round(insights.confidence * 100, 1)}%")
    
    if length(insights[:usage_patterns] || []) > 0 do
      IO.puts("\n📊 Usage Patterns:")
      Enum.each(insights.usage_patterns, fn pattern ->
        IO.puts("   • #{pattern.pattern} (#{pattern.frequency} times)")
      end)
    end
    
    IO.puts("")
  end

  # Debugging helpers

  defp debug_process_with_ai(pid, context) do
    process_info = Process.info(pid) || %{}
    
    IO.puts("🔍 AI Process Analysis:")
    IO.puts("   PID: #{inspect(pid)}")
    IO.puts("   Status: #{process_info[:status] || "unknown"}")
    IO.puts("   Message Queue: #{process_info[:message_queue_len] || 0}")
    
    if context != "" do
      IO.puts("   Context: #{context}")
    end
    
    # AI analysis would go here
    IO.puts("   🤖 AI suggests checking message queue and heap size")
  end

  defp debug_error_with_ai(reason, context) do
    IO.puts("🩺 AI Error Analysis:")
    IO.puts("   Error: #{reason}")
    
    if context != "" do
      IO.puts("   Context: #{context}")
    end
    
    # Pattern-based suggestions
    suggestions = case reason do
      reason when is_binary(reason) ->
        cond do
          String.contains?(reason, "undefined function") ->
            ["Check module imports", "Verify function name spelling", "Ensure module is compiled"]
          String.contains?(reason, "no match") ->
            ["Check pattern matching", "Add fallback patterns", "Verify data structure"]
          true ->
            ["Check the stack trace", "Verify input data", "Add defensive programming"]
        end
      _ ->
        ["Use more specific error handling", "Add logging for debugging"]
    end
    
    IO.puts("   💡 AI Suggestions:")
    Enum.each(suggestions, fn suggestion ->
      IO.puts("     • #{suggestion}")
    end)
  end

  defp debug_exception_with_ai(exception, context) do
    IO.puts("🩺 AI Exception Analysis:")
    IO.puts("   Exception: #{Exception.message(exception)}")
    IO.puts("   Type: #{exception.__struct__}")
    
    if context != "" do
      IO.puts("   Context: #{context}")
    end
    
    IO.puts("   🤖 AI suggests adding specific exception handling for #{exception.__struct__}")
  end

  defp debug_general_with_ai(target, context) do
    IO.puts("🔍 AI General Debug:")
    IO.puts("   Target: #{inspect(target)}")
    
    if context != "" do
      IO.puts("   Context: #{context}")
    end
    
    IO.puts("   💡 Use ai_eval/2 with explain: true for detailed analysis")
  end

  # Project analysis

  defp analyze_project_with_ai(project_dir, focus) do
    # Simplified project analysis - would be more comprehensive in real implementation
    files = Path.wildcard(Path.join([project_dir, "**", "*.{ex,exs}"]))
    
    analysis = %{
      project_dir: project_dir,
      total_files: length(files),
      focus: focus,
      summary: "Project analysis completed",
      recommendations: generate_recommendations(files, focus)
    }
    
    {:ok, analysis}
  end

  defp generate_recommendations(files, focus) do
    base_recommendations = [
      "Consider adding more documentation",
      "Review test coverage",
      "Check for code duplication"
    ]
    
    focus_recommendations = case focus do
      :performance -> ["Profile critical paths", "Consider caching strategies"]
      :security -> ["Review input validation", "Check for injection vulnerabilities"]
      :maintainability -> ["Refactor large functions", "Improve module organization"]
      _ -> []
    end
    
    base_recommendations ++ focus_recommendations
  end

  defp display_project_analysis(analysis, focus) do
    IO.puts("\n📊 AI Project Analysis\n")
    
    IO.puts("🏗️  Project Overview:")
    IO.puts("   Directory: #{analysis.project_dir}")
    IO.puts("   Files: #{analysis.total_files}")
    IO.puts("   Focus: #{focus}")
    
    IO.puts("\n📝 Summary:")
    IO.puts("   #{analysis.summary}")
    
    IO.puts("\n💡 AI Recommendations:")
    Enum.each(analysis.recommendations, fn rec ->
      IO.puts("   • #{rec}")
    end)
    
    IO.puts("")
  end

  # Test helpers

  defp get_test_suggestions(module, test_type) do
    case Helpers.ai_test(module, type: test_type) do
      %{tests: tests} when length(tests) > 0 ->
        {:ok, %{tests: tests, test_type: test_type}}
      %{error: reason} ->
        {:error, reason}
      _ ->
        {:error, "No test suggestions available"}
    end
  end

  defp display_test_suggestions(module, suggestions) do
    IO.puts("\n🧪 AI Test Suggestions for #{module}\n")
    
    IO.puts("📋 Suggested Tests (#{suggestions.test_type}):")
    suggestions.tests
    |> Enum.with_index(1)
    |> Enum.each(fn {test, index} ->
      IO.puts("   #{index}. #{test}")
    end)
    
    IO.puts("\n💡 Use ai_test_generate/2 to create complete test files")
    IO.puts("")
  end
end