defmodule Aiex.CLI.Commands.Pipeline do
  @moduledoc """
  Pipeline command handler for chaining AI operations.
  
  Provides command-line interface to execute complex AI workflows
  by chaining multiple AI operations together with various execution modes.
  """

  @behaviour Aiex.CLI.Commands.CommandBehaviour

  alias Aiex.AI.Pipeline
  alias Aiex.CLI.Commands.AI.OutputFormatter

  @impl true
  def execute({[:pipeline], %Optimus.ParseResult{options: options, flags: flags}}) do
    # Extract options
    pipeline_spec = Map.get(options, :spec)
    input_file = Map.get(options, :input)
    output_file = Map.get(options, :output)
    mode = String.to_atom(Map.get(options, :mode, "sequential"))
    
    # Extract flags
    validate_only = Map.get(flags, :validate, false)
    error_handling = if Map.get(flags, :continue_on_error, false), do: :continue_on_error, else: :stop_on_error
    verbose = Map.get(flags, :verbose, false)
    
    # Validate required parameters
    if !pipeline_spec do
      {:error, "Pipeline specification is required. Use --spec option."}
    else
    
    # Parse pipeline specification
    case Pipeline.from_string(pipeline_spec) do
      {:ok, pipeline_steps} ->
        if validate_only do
          validate_pipeline_only(pipeline_steps)
        else
          execute_pipeline(pipeline_steps, %{
            input: read_input(input_file),
            output_file: output_file,
            mode: mode,
            error_handling: error_handling,
            verbose: verbose
          })
        end
        
      {:error, reason} ->
        {:error, "Failed to parse pipeline: #{reason}"}
    end
    end
  end

  @impl true
  def execute({[:pipeline], %Optimus.ParseResult{args: args}}) when map_size(args) > 0 do
    case Map.keys(args) do
      [:validate] -> handle_validate_subcommand(args[:validate])
      [:list] -> handle_list_subcommand()
      [:examples] -> handle_examples_subcommand()
      _ -> {:error, "Unknown pipeline subcommand. Use 'aiex help pipeline' for usage information."}
    end
  end

  @impl true 
  def execute(_) do
    {:error, "Invalid pipeline command usage. Use 'aiex help pipeline' for usage information."}
  end

  # Subcommand handlers

  defp handle_validate_subcommand(spec) do
    case Pipeline.from_string(spec) do
      {:ok, pipeline_steps} ->
        case Pipeline.validate_pipeline(pipeline_steps) do
          :ok ->
            {:ok, {:pipeline_validation, "✅ Pipeline is valid", %{
              steps: length(pipeline_steps),
              operations: extract_operations(pipeline_steps)
            }}}
            
          {:error, errors} ->
            {:error, "Pipeline validation failed:\n#{format_validation_errors(errors)}"}
        end
        
      {:error, reason} ->
        {:error, "Pipeline parsing failed: #{reason}"}
    end
  end

  defp handle_list_subcommand do
    operations = Pipeline.available_operations()
    
    formatted_output = """
    📋 Available Pipeline Operations
    #{String.duplicate("=", 50)}
    
    🤖 AI Operations:
    #{format_operation_list(operations.ai_operations)}
    
    🔄 Transformers:
    #{format_operation_list(operations.transformers)}
    
    ❓ Conditions:
    #{format_operation_list(operations.conditions)}
    
    🛠️  Utilities:
    #{format_operation_list(operations.utilities)}
    """
    
    {:ok, {:pipeline_operations, formatted_output}}
  end

  defp handle_examples_subcommand do
    examples = get_pipeline_examples()
    
    formatted_output = """
    💡 Pipeline Examples
    #{String.duplicate("=", 60)}
    
    #{format_examples(examples)}
    """
    
    {:ok, {:pipeline_examples, formatted_output}}
  end

  # Pipeline execution

  defp validate_pipeline_only(pipeline_steps) do
    case Pipeline.validate_pipeline(pipeline_steps) do
      :ok ->
        summary = %{
          valid: true,
          step_count: length(pipeline_steps),
          operations: extract_operations(pipeline_steps),
          estimated_duration: estimate_duration(pipeline_steps)
        }
        
        {:ok, {:pipeline_validation, "Pipeline validation successful", summary}}
        
      {:error, errors} ->
        {:error, "Pipeline validation failed:\n#{format_validation_errors(errors)}"}
    end
  end

  defp execute_pipeline(pipeline_steps, opts) do
    if opts.verbose do
      IO.puts("🚀 Starting pipeline execution:")
      IO.puts("   Steps: #{length(pipeline_steps)}")
      IO.puts("   Mode: #{opts.mode}")
      IO.puts("   Error handling: #{opts.error_handling}")
      if opts.input, do: IO.puts("   Input: from file")
      if opts.output_file, do: IO.puts("   Output: to #{opts.output_file}")
      IO.puts("")
    end
    
    pipeline_opts = [
      input: opts.input,
      mode: opts.mode,
      error_handling: opts.error_handling
    ]
    
    case Pipeline.execute(pipeline_steps, pipeline_opts) do
      {:ok, result} ->
        # Handle output
        formatted_result = format_pipeline_result(result)
        
        case write_output(formatted_result, opts.output_file) do
          :ok ->
            if opts.verbose do
              IO.puts("✅ Pipeline completed successfully!")
              IO.puts("   Duration: #{result.metadata.duration_ms}ms")
              IO.puts("   Steps completed: #{length(result.results)}")
            end
            
            {:ok, {:pipeline_execution, "Pipeline executed successfully", result}}
            
          {:error, reason} ->
            {:error, "Pipeline executed but failed to write output: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "Pipeline execution failed: #{reason}"}
    end
  end

  # Helper functions

  defp read_input(nil), do: nil
  defp read_input(file_path) do
    case File.read(file_path) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end

  defp write_output(content, nil) do
    IO.puts(content)
    :ok
  end
  defp write_output(content, output_file) do
    case File.write(output_file, content) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_operations(pipeline_steps) do
    pipeline_steps
    |> Enum.map(fn step -> step.operation end)
    |> Enum.uniq()
  end

  defp estimate_duration(pipeline_steps) do
    # Simple duration estimation based on operation types
    base_time_per_step = 5000  # 5 seconds per step
    total_steps = length(pipeline_steps)
    estimated_ms = total_steps * base_time_per_step
    
    "~#{div(estimated_ms, 1000)}s"
  end

  defp format_validation_errors(errors) do
    errors
    |> Enum.map(fn error -> "  • #{error}" end)
    |> Enum.join("\n")
  end

  defp format_operation_list(operations) do
    operations
    |> Enum.map(fn op -> "   • #{op}" end)
    |> Enum.join("\n")
  end

  defp format_pipeline_result(result) do
    """
    🎯 Pipeline Execution Results
    #{String.duplicate("=", 50)}
    
    📊 Summary:
       #{result.summary}
       Duration: #{result.metadata.duration_ms}ms
       Steps: #{length(result.results)}
    
    📋 Results:
    #{format_step_results(result.results)}
    
    #{format_final_output(result.final_output)}
    """
  end

  defp format_step_results(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map(fn {result, index} ->
      operation = Map.get(result, :operation, "unknown")
      status = if Map.has_key?(result, :error), do: "❌ Failed", else: "✅ Success"
      "   #{index}. #{operation}: #{status}"
    end)
    |> Enum.join("\n")
  end

  defp format_final_output(nil), do: ""
  defp format_final_output(output) do
    """
    
    🎯 Final Output:
    #{String.duplicate("-", 40)}
    #{inspect(output, pretty: true, limit: :infinity)}
    #{String.duplicate("-", 40)}
    """
  end

  defp get_pipeline_examples do
    [
      %{
        name: "Code Quality Pipeline",
        description: "Analyze code, suggest refactoring, and generate tests",
        spec: "analyze file:lib/module.ex | refactor type:quality | test_generate coverage:0.9"
      },
      %{
        name: "Documentation Pipeline", 
        description: "Explain code and generate documentation",
        spec: "explain level:detailed | extract_insights | document format:markdown"
      },
      %{
        name: "Performance Pipeline",
        description: "Analyze performance and suggest optimizations",
        spec: "analyze type:performance | refactor type:performance | explain level:advanced"
      },
      %{
        name: "Parallel Analysis",
        description: "Run multiple analyses in parallel",
        spec: "analyze type:quality | analyze type:security | analyze type:performance",
        mode: "parallel"
      },
      %{
        name: "Conditional Workflow",
        description: "Conditional refactoring based on quality score",
        spec: "analyze | if:quality<0.8 refactor | test_generate",
        mode: "conditional"
      }
    ]
  end

  defp format_examples(examples) do
    examples
    |> Enum.map(fn example ->
      """
      📌 #{example.name}
         #{example.description}
         
         Pipeline: #{example.spec}
         #{if Map.has_key?(example, :mode), do: "Mode: #{example.mode}", else: ""}
         
         Usage:
         aiex pipeline --spec "#{example.spec}"#{if Map.has_key?(example, :mode), do: " --mode #{example.mode}", else: ""}
      """
    end)
    |> Enum.join("\n#{String.duplicate("-", 60)}\n")
  end
end