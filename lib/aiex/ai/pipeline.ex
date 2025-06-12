defmodule Aiex.AI.Pipeline do
  @moduledoc """
  AI operation pipeline support for chaining AI operations.
  
  Provides a powerful pipeline system that allows users to chain multiple
  AI operations together, passing results from one operation to the next
  for complex workflows and analysis.
  """

  alias Aiex.AI.Coordinators.CodingAssistant
  alias Aiex.AI.WorkflowOrchestrator
  alias Aiex.CLI.Commands.AI.ProgressReporter

  require Logger

  @type pipeline_step :: %{
    operation: atom(),
    params: map(),
    transform: function() | nil,
    condition: function() | nil
  }

  @type pipeline_context :: %{
    input: any(),
    results: list(),
    metadata: map(),
    error_handling: atom()
  }

  @type pipeline_result :: {:ok, any()} | {:error, String.t()}

  # Pipeline execution modes
  @execution_modes [:sequential, :parallel, :conditional, :streaming]

  # Built-in transformers
  @transformers %{
    extract_code: &__MODULE__.extract_code_from_response/1,
    extract_insights: &__MODULE__.extract_insights_from_response/1,
    format_markdown: &__MODULE__.format_as_markdown/1,
    combine_results: &__MODULE__.combine_multiple_results/1,
    filter_suggestions: &__MODULE__.filter_relevant_suggestions/1
  }

  @doc """
  Execute a pipeline of AI operations.
  
  ## Examples
  
      # Simple sequential pipeline
      pipeline = [
        %{operation: :analyze, params: %{file: "lib/module.ex"}},
        %{operation: :refactor, params: %{type: "performance"}},
        %{operation: :test_generate, params: %{coverage: 0.9}}
      ]
      
      Pipeline.execute(pipeline, mode: :sequential)
      
      # Pipeline with transformations
      pipeline = [
        %{operation: :analyze, params: %{file: "lib/module.ex"}},
        %{operation: :explain, params: %{level: "detailed"}, 
          transform: &Pipeline.extract_code/1},
        %{operation: :document, params: %{format: "markdown"}}
      ]
      
      Pipeline.execute(pipeline, mode: :streaming)
  """
  def execute(pipeline_steps, opts \\ []) when is_list(pipeline_steps) do
    mode = Keyword.get(opts, :mode, :sequential)
    error_handling = Keyword.get(opts, :error_handling, :stop_on_error)
    input = Keyword.get(opts, :input)
    
    if mode not in @execution_modes do
      {:error, "Invalid execution mode: #{mode}. Available: #{inspect(@execution_modes)}"}
    else
      context = %{
      input: input,
      results: [],
      metadata: %{
        started_at: DateTime.utc_now(),
        mode: mode,
        total_steps: length(pipeline_steps)
      },
      error_handling: error_handling
    }
    
    ProgressReporter.start_pipeline(length(pipeline_steps), mode)
    
    result = case mode do
      :sequential -> execute_sequential(pipeline_steps, context)
      :parallel -> execute_parallel(pipeline_steps, context)
      :conditional -> execute_conditional(pipeline_steps, context)
      :streaming -> execute_streaming(pipeline_steps, context)
    end
    
    case result do
      {:ok, final_context} ->
        ProgressReporter.complete("Pipeline completed successfully!")
        {:ok, format_pipeline_result(final_context)}
        
      {:error, reason} ->
        ProgressReporter.error("Pipeline failed: #{reason}")
        {:error, reason}
    end
    end
  end

  @doc """
  Create a pipeline from a pipeline specification string.
  
  ## Examples
  
      # Simple chain
      "analyze file:lib/module.ex | refactor type:performance | test_generate"
      
      # With transformations
      "analyze file:lib/module.ex | extract_code | explain level:detailed | format_markdown"
      
      # Conditional execution
      "analyze file:lib/module.ex | if:quality<0.8 refactor | test_generate coverage:0.9"
  """
  def from_string(pipeline_spec) when is_binary(pipeline_spec) do
    pipeline_spec
    |> String.split("|")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_pipeline_step/1)
    |> case do
      steps when is_list(steps) ->
        if Enum.all?(steps, &match?({:ok, _}, &1)) do
          {:ok, Enum.map(steps, fn {:ok, step} -> step end)}
        else
          errors = Enum.filter(steps, &match?({:error, _}, &1))
          {:error, "Pipeline parsing errors: #{inspect(errors)}"}
        end
        
      error ->
        {:error, "Failed to parse pipeline: #{inspect(error)}"}
    end
  end

  @doc """
  Register a custom transformer function.
  
  ## Examples
  
      Pipeline.register_transformer(:my_transformer, fn result ->
        # Custom transformation logic
        {:ok, transformed_result}
      end)
  """
  def register_transformer(name, function) when is_atom(name) and is_function(function) do
    # In a real implementation, this would store in ETS or a registry
    Agent.start_link(fn -> Map.put(@transformers, name, function) end, name: __MODULE__)
    :ok
  end

  @doc """
  List available pipeline operations.
  """
  def available_operations do
    %{
      ai_operations: [:analyze, :generate, :explain, :refactor, :test_generate, :document],
      transformers: Map.keys(@transformers),
      conditions: [:if, :unless, :when, :while],
      utilities: [:save, :load, :merge, :split, :filter]
    }
  end

  @doc """
  Validate a pipeline before execution.
  """
  def validate_pipeline(pipeline_steps) when is_list(pipeline_steps) do
    errors = Enum.with_index(pipeline_steps)
    |> Enum.flat_map(fn {step, index} ->
      case validate_step(step, index) do
        {:ok, _} -> []
        {:error, error} -> [error]
      end
    end)
    
    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # Sequential execution - one step after another
  defp execute_sequential(steps, context) do
    Enum.with_index(steps)
    |> Enum.reduce_while({:ok, context}, fn {step, index}, {:ok, acc_context} ->
      ProgressReporter.update_pipeline_step(step.operation, index + 1, context.metadata.total_steps)
      
      case execute_single_step(step, acc_context) do
        {:ok, result, updated_context} ->
          new_context = %{updated_context | 
            results: acc_context.results ++ [result],
            input: get_output_for_next_step(result, step)
          }
          {:cont, {:ok, new_context}}
          
        {:error, reason} ->
          case acc_context.error_handling do
            :stop_on_error -> {:halt, {:error, "Step #{index + 1} failed: #{reason}"}}
            :continue_on_error -> 
              error_result = %{error: reason, step: index + 1}
              new_context = %{acc_context | results: acc_context.results ++ [error_result]}
              {:cont, {:ok, new_context}}
            :skip_on_error ->
              {:cont, {:ok, acc_context}}
          end
      end
    end)
  end

  # Parallel execution - all steps run concurrently
  defp execute_parallel(steps, context) do
    tasks = Enum.with_index(steps)
    |> Enum.map(fn {step, index} ->
      Task.async(fn ->
        Logger.debug("Starting parallel step #{index + 1}")
        execute_single_step(step, context)
      end)
    end)
    
    results = Task.await_many(tasks, 120_000)  # 2 minute timeout
    
    # Check if any steps failed
    errors = Enum.with_index(results)
    |> Enum.filter(fn {result, _index} -> match?({:error, _}, result) end)
    
    case {errors, context.error_handling} do
      {[], _} ->
        # All successful
        successful_results = Enum.map(results, fn {:ok, result, _context} -> result end)
        final_context = %{context | 
          results: successful_results,
          input: combine_parallel_outputs(successful_results)
        }
        {:ok, final_context}
        
      {errors, :stop_on_error} ->
        {:error, "Parallel execution failed: #{inspect(errors)}"}
        
      {_errors, _} ->
        # Continue with successful results only
        successful_results = results
        |> Enum.filter(fn result -> match?({:ok, _, _}, result) end)
        |> Enum.map(fn {:ok, result, _context} -> result end)
        
        final_context = %{context | results: successful_results}
        {:ok, final_context}
    end
  end

  # Conditional execution - steps run based on conditions
  defp execute_conditional(steps, context) do
    Enum.with_index(steps)
    |> Enum.reduce_while({:ok, context}, fn {step, index}, {:ok, acc_context} ->
      if should_execute_step?(step, acc_context) do
        ProgressReporter.update_pipeline_step(step.operation, index + 1, context.metadata.total_steps)
        
        case execute_single_step(step, acc_context) do
          {:ok, result, updated_context} ->
            new_context = %{updated_context | 
              results: acc_context.results ++ [result],
              input: get_output_for_next_step(result, step)
            }
            {:cont, {:ok, new_context}}
            
          {:error, reason} ->
            {:halt, {:error, "Conditional step #{index + 1} failed: #{reason}"}}
        end
      else
        Logger.debug("Skipping conditional step #{index + 1}")
        {:cont, {:ok, acc_context}}
      end
    end)
  end

  # Streaming execution - results stream as they're available
  defp execute_streaming(steps, context) do
    stream = Stream.with_index(steps)
    |> Stream.map(fn {step, index} ->
      ProgressReporter.update_pipeline_step(step.operation, index + 1, length(steps))
      
      case execute_single_step(step, context) do
        {:ok, result, _updated_context} ->
          {:ok, %{step: index + 1, result: result, timestamp: DateTime.utc_now()}}
        {:error, reason} ->
          {:error, %{step: index + 1, error: reason, timestamp: DateTime.utc_now()}}
      end
    end)
    
    results = Enum.to_list(stream)
    successful_results = results
    |> Enum.filter(fn result -> match?({:ok, _}, result) end)
    |> Enum.map(fn {:ok, data} -> data.result end)
    
    final_context = %{context | results: successful_results}
    {:ok, final_context}
  end

  # Execute a single pipeline step
  defp execute_single_step(step, context) do
    with {:ok, validated_step} <- validate_step(step, 0),
         {:ok, result} <- execute_operation(validated_step, context),
         {:ok, transformed_result} <- apply_transformation(result, validated_step),
         :ok <- update_progress() do
      
      updated_context = Map.put(context, :last_result, transformed_result)
      {:ok, transformed_result, updated_context}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_operation(%{operation: operation, params: params}, context) do
    case operation do
      :analyze -> execute_analyze(params, context)
      :generate -> execute_generate(params, context)
      :explain -> execute_explain(params, context)
      :refactor -> execute_refactor(params, context)
      :test_generate -> execute_test_generate(params, context)
      :document -> execute_document(params, context)
      :workflow -> execute_workflow(params, context)
      _ -> {:error, "Unknown operation: #{operation}"}
    end
  end

  # AI Operation implementations
  
  defp execute_analyze(params, context) do
    content = Map.get(params, :content) || context.input
    analysis_type = Map.get(params, :type, "quality")
    
    request = %{
      intent: :code_review,
      description: "Pipeline analysis: #{analysis_type}",
      code: content,
      analysis_type: String.to_atom(analysis_type),
      context: build_pipeline_context(context)
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, %{operation: :analyze, result: response, params: params}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_generate(params, context) do
    description = Map.get(params, :description) || Map.get(params, :requirements)
    generation_type = Map.get(params, :type, "code")
    
    request = %{
      intent: :implement_feature,
      description: description,
      generation_type: String.to_atom(generation_type),
      context: build_pipeline_context(context)
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, %{operation: :generate, result: response, params: params}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_explain(params, context) do
    content = Map.get(params, :content) || context.input
    level = Map.get(params, :level, "intermediate")
    
    request = %{
      intent: :explain_codebase,
      description: "Pipeline explanation",
      code: content,
      explanation_level: String.to_atom(level),
      context: build_pipeline_context(context)
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, %{operation: :explain, result: response, params: params}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_refactor(params, context) do
    content = Map.get(params, :content) || context.input
    refactor_type = Map.get(params, :type, "all")
    
    request = %{
      intent: :refactor_code,
      description: "Pipeline refactoring: #{refactor_type}",
      code: content,
      refactor_type: String.to_atom(refactor_type),
      context: build_pipeline_context(context)
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, %{operation: :refactor, result: response, params: params}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_test_generate(params, context) do
    content = Map.get(params, :content) || context.input
    coverage = Map.get(params, :coverage, 0.8)
    
    # This would integrate with test generation workflow
    workflow_context = Map.merge(build_pipeline_context(context), %{
      code: content,
      coverage_target: coverage
    })
    
    case WorkflowOrchestrator.execute_template("test_generation", workflow_context) do
      {:ok, _workflow_id, workflow_state} -> 
        {:ok, %{operation: :test_generate, result: workflow_state, params: params}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_document(params, context) do
    content = Map.get(params, :content) || context.input
    format = Map.get(params, :format, "markdown")
    
    # This would be a documentation generation request
    request = %{
      intent: :generate_documentation,
      description: "Generate documentation",
      code: content,
      format: String.to_atom(format),
      context: build_pipeline_context(context)
    }
    
    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} -> {:ok, %{operation: :document, result: response, params: params}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_workflow(params, context) do
    template = Map.get(params, :template)
    workflow_context = Map.merge(build_pipeline_context(context), params)
    
    case WorkflowOrchestrator.execute_template(template, workflow_context) do
      {:ok, _workflow_id, workflow_state} -> 
        {:ok, %{operation: :workflow, result: workflow_state, params: params}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Transformation functions

  defp apply_transformation(result, %{transform: nil}), do: {:ok, result}
  defp apply_transformation(result, %{transform: transform_fn}) when is_function(transform_fn) do
    try do
      {:ok, transform_fn.(result)}
    rescue
      error -> {:error, "Transformation failed: #{Exception.message(error)}"}
    end
  end
  defp apply_transformation(result, %{transform: transform_name}) when is_atom(transform_name) do
    case Map.get(@transformers, transform_name) do
      nil -> {:error, "Unknown transformer: #{transform_name}"}
      transform_fn -> apply_transformation(result, %{transform: transform_fn})
    end
  end
  defp apply_transformation(result, _), do: {:ok, result}

  # Built-in transformer implementations

  def extract_code_from_response(%{result: %{artifacts: %{code: code}}}), do: code
  def extract_code_from_response(%{result: response}) when is_map(response) do
    # Try to extract code from various response formats
    response.artifacts[:code] || response.content || response.response || ""
  end
  def extract_code_from_response(other), do: inspect(other)

  def extract_insights_from_response(%{result: response}) when is_map(response) do
    %{
      insights: response.insights || response.recommendations || [],
      confidence: response.confidence || response.metadata[:confidence] || 0.5,
      summary: response.summary || response.description || "No summary available"
    }
  end
  def extract_insights_from_response(other), do: %{insights: [], confidence: 0.0, summary: inspect(other)}

  def format_as_markdown(content) when is_binary(content) do
    """
    ```elixir
    #{content}
    ```
    """
  end
  def format_as_markdown(%{} = data) do
    data
    |> Enum.map(fn {key, value} ->
      "## #{String.capitalize(to_string(key))}\n\n#{value}\n"
    end)
    |> Enum.join("\n")
  end
  def format_as_markdown(other), do: "```\n#{inspect(other, pretty: true)}\n```"

  def combine_multiple_results(results) when is_list(results) do
    %{
      combined_results: results,
      summary: "Combined #{length(results)} results",
      metadata: %{
        result_count: length(results),
        combined_at: DateTime.utc_now()
      }
    }
  end
  def combine_multiple_results(single_result), do: single_result

  def filter_relevant_suggestions(%{suggestions: suggestions}) when is_list(suggestions) do
    # Simple relevance filtering - could be enhanced with ML
    filtered = Enum.filter(suggestions, fn suggestion ->
      String.length(inspect(suggestion)) > 20  # Basic length filter
    end)
    
    %{suggestions: filtered, filtered_count: length(suggestions) - length(filtered)}
  end
  def filter_relevant_suggestions(other), do: other

  # Helper functions

  defp parse_pipeline_step(step_string) do
    case String.split(step_string, " ", parts: 2) do
      [operation] ->
        {:ok, %{operation: String.to_atom(operation), params: %{}}}
        
      [operation, params_string] ->
        case parse_params(params_string) do
          {:ok, params} -> {:ok, %{operation: String.to_atom(operation), params: params}}
          {:error, reason} -> {:error, reason}
        end
    end
  rescue
    _ -> {:error, "Invalid step format: #{step_string}"}
  end

  defp parse_params(params_string) do
    # Simple key:value parsing - could be enhanced
    params = params_string
    |> String.split(" ")
    |> Enum.map(fn param ->
      case String.split(param, ":", parts: 2) do
        [key, value] -> {String.to_atom(key), value}
        [key] -> {String.to_atom(key), true}
      end
    end)
    |> Enum.into(%{})
    
    {:ok, params}
  rescue
    _ -> {:error, "Invalid parameters: #{params_string}"}
  end

  defp validate_step(%{operation: operation} = step, index) do
    available_ops = available_operations().ai_operations
    
    cond do
      operation not in available_ops ->
        {:error, "Step #{index + 1}: Unknown operation '#{operation}'. Available: #{inspect(available_ops)}"}
      
      not is_map(step.params || %{}) ->
        {:error, "Step #{index + 1}: Invalid parameters format"}
      
      true ->
        {:ok, step}
    end
  end
  defp validate_step(step, index) do
    {:error, "Step #{index + 1}: Missing operation field in #{inspect(step)}"}
  end

  defp should_execute_step?(%{condition: nil}, _context), do: true
  defp should_execute_step?(%{condition: condition_fn}, context) when is_function(condition_fn) do
    try do
      condition_fn.(context)
    rescue
      _ -> false
    end
  end
  defp should_execute_step?(_, _), do: true

  defp get_output_for_next_step(result, %{transform: _}), do: result
  defp get_output_for_next_step(%{result: response} = full_result, _) do
    # Extract the most useful part for the next step
    cond do
      is_map(response) and Map.has_key?(response, :artifacts) ->
        response.artifacts.code || response.content || response.response
      is_map(response) ->
        response.content || response.response || inspect(response)
      true ->
        full_result
    end
  end

  defp combine_parallel_outputs(results) do
    # Combine results from parallel execution
    %{
      parallel_results: results,
      combined_output: Enum.map(results, &extract_main_content/1) |> Enum.join("\n\n"),
      metadata: %{count: length(results)}
    }
  end

  defp extract_main_content(%{result: response}) when is_map(response) do
    response.content || response.response || inspect(response)
  end
  defp extract_main_content(other), do: inspect(other)

  defp build_pipeline_context(context) do
    %{
      pipeline_mode: context.metadata.mode,
      step_count: length(context.results),
      previous_results: Enum.take(context.results, -3),  # Last 3 results for context
      input: context.input
    }
  end

  defp format_pipeline_result(context) do
    %{
      results: context.results,
      summary: "Pipeline completed with #{length(context.results)} steps",
      metadata: Map.merge(context.metadata, %{
        completed_at: DateTime.utc_now(),
        duration_ms: DateTime.diff(DateTime.utc_now(), context.metadata.started_at, :millisecond)
      }),
      final_output: List.last(context.results)
    }
  end

  defp update_progress do
    # This would update progress reporting in a real implementation
    :ok
  end
end