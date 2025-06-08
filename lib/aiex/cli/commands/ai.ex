defmodule Aiex.CLI.Commands.AI do
  @moduledoc """
  AI command handler for comprehensive AI-powered coding assistance.
  """
  
  @behaviour Aiex.CLI.Commands.CommandBehaviour
  
  alias Aiex.AI.Coordinators.{CodingAssistant, ConversationManager}
  alias Aiex.AI.WorkflowOrchestrator
  alias Aiex.CLI.Commands.AI.{ProgressReporter, OutputFormatter}
  
  require Logger
  
  @impl true
  def execute({[:ai], %Optimus.ParseResult{args: args} = parsed}) do
    case Map.keys(args) do
      [:analyze] -> ai_analyze(parsed)
      [:generate] -> ai_generate(parsed)
      [:explain] -> ai_explain(parsed)
      [:refactor] -> ai_refactor(parsed)
      [:workflow] -> ai_workflow(parsed)
      [:chat] -> ai_chat(parsed)
      [] -> {:error, "AI subcommand required. Use 'aiex help ai' for available commands."}
      unknown -> {:error, "Unknown AI subcommand: #{inspect(unknown)}. Use 'aiex help ai' for available commands."}
    end
  end
  
  @impl true
  def execute(_) do
    {:error, "Invalid AI command usage. Use 'aiex help ai' for usage information."}
  end
  
  # AI Analyze - Code analysis with AI insights
  defp ai_analyze(%Optimus.ParseResult{args: %{analyze: _}, options: options}) do
    file_path = Map.get(options, :file)
    analysis_type = Map.get(options, :type, "quality")
    output_format = Map.get(options, :output, "text")
    
    cond do
      !file_path ->
        {:error, "File path is required for analysis. Use --file option."}
      
      !File.exists?(file_path) ->
        {:error, "File not found: #{file_path}"}
      
      true ->
        execute_analysis(file_path, analysis_type, output_format)
    end
  end
  
  # AI Generate - Code generation with AI
  defp ai_generate(%Optimus.ParseResult{args: %{generate: _}, options: options}) do
    generation_type = Map.get(options, :type)
    requirements = Map.get(options, :requirements)
    context_file = Map.get(options, :context)
    output_file = Map.get(options, :output)
    
    cond do
      !generation_type ->
        {:error, "Generation type is required. Use --type option."}
        
      !requirements ->
        {:error, "Requirements description is required. Use --requirements option."}
        
      true ->
        execute_generation(generation_type, requirements, context_file, output_file)
    end
  end
  
  # AI Explain - Code explanations with AI
  defp ai_explain(%Optimus.ParseResult{args: %{explain: _}, options: options}) do
    file_path = Map.get(options, :file)
    level = Map.get(options, :level, "intermediate")
    focus = Map.get(options, :focus, "comprehensive")
    
    cond do
      !file_path ->
        {:error, "File path is required for explanation. Use --file option."}
      
      !File.exists?(file_path) ->
        {:error, "File not found: #{file_path}"}
      
      true ->
        execute_explanation(file_path, level, focus)
    end
  end
  
  # AI Refactor - Refactoring suggestions and implementation
  defp ai_refactor(%Optimus.ParseResult{args: %{refactor: _}, options: options, flags: flags}) do
    file_path = Map.get(options, :file)
    refactor_type = Map.get(options, :type, "all")
    apply_changes = Map.get(flags, :apply, false)
    show_preview = Map.get(flags, :preview, false)
    
    cond do
      !file_path ->
        {:error, "File path is required for refactoring. Use --file option."}
      
      !File.exists?(file_path) ->
        {:error, "File not found: #{file_path}"}
      
      true ->
        execute_refactoring(file_path, refactor_type, apply_changes, show_preview)
    end
  end
  
  # AI Workflow - Execute AI workflow templates
  defp ai_workflow(%Optimus.ParseResult{args: %{workflow: _}, options: options}) do
    template = Map.get(options, :template)
    context_file = Map.get(options, :context)
    description = Map.get(options, :description)
    mode = Map.get(options, :mode, "sequential")
    
    if !template do
      {:error, "Workflow template is required. Use --template option."}
    else
      execute_workflow(template, context_file, description, mode)
    end
  end
  
  # AI Chat - Interactive AI chat sessions
  defp ai_chat(%Optimus.ParseResult{args: %{chat: _}, options: options}) do
    conversation_type = Map.get(options, :conversation_type, "coding")
    context_dir = Map.get(options, :context, ".")
    
    execute_chat(conversation_type, context_dir)
  end
  
  # Helper function implementations
  
  defp execute_analysis(file_path, analysis_type, output_format) do
    ProgressReporter.start_analysis(analysis_type, Path.basename(file_path))
    
    try do
      ProgressReporter.update_analysis("Reading file")
      {:ok, content} = File.read(file_path)
      
      ProgressReporter.update_analysis("Preparing analysis")
      request = %{
        intent: :code_review,
        description: "CLI analysis: #{analysis_type}",
        code: content,
        file_path: file_path,
        analysis_type: String.to_atom(analysis_type),
        context: %{
          cli_context: true,
          output_format: output_format
        }
      }
      
      ProgressReporter.update_analysis("Running AI analysis")
      case CodingAssistant.handle_coding_request(request) do
        {:ok, response} ->
          ProgressReporter.complete("Analysis completed successfully!")
          formatted_output = OutputFormatter.format_analysis_result(response, output_format)
          {:ok, {:ai_analysis, formatted_output, %{file: file_path, type: analysis_type}}}
          
        {:error, reason} ->
          ProgressReporter.error("Analysis failed: #{reason}")
          {:error, "AI analysis failed: #{reason}"}
      end
      
    rescue
      error ->
        ProgressReporter.error("Analysis error: #{Exception.message(error)}")
        {:error, "Analysis failed: #{Exception.message(error)}"}
    end
  end
  
  defp execute_generation(generation_type, requirements, context_file, output_file) do
    ProgressReporter.start_generation(generation_type)
    
    try do
      context_code = if context_file && File.exists?(context_file) do
        ProgressReporter.update_generation_stage(:planning, 0.3)
        {:ok, content} = File.read(context_file)
        content
      else
        nil
      end
      
      ProgressReporter.update_generation_stage(:planning, 0.7)
      request = %{
        intent: :implement_feature,
        description: requirements,
        generation_type: String.to_atom(generation_type),
        context: %{
          cli_context: true,
          context_code: context_code,
          output_file: output_file
        }
      }
      
      ProgressReporter.update_generation_stage(:generation, 0.2)
      case CodingAssistant.handle_coding_request(request) do
        {:ok, response} ->
          ProgressReporter.update_generation_stage(:validation, 0.8)
          formatted_output = OutputFormatter.format_generation_result(response, generation_type)
          
          case write_generated_output(formatted_output, output_file) do
            :ok ->
              ProgressReporter.update_generation_stage(:complete, 1.0)
              ProgressReporter.complete("Code generation completed successfully!")
              
              success_msg = if output_file do
                "Generated #{generation_type} code written to #{output_file}"
              else
                "Generated #{generation_type} code"
              end
              
              {:ok, {:ai_generation, success_msg, %{type: generation_type, output: formatted_output}}}
              
            {:error, reason} ->
              ProgressReporter.error("Failed to write output: #{reason}")
              {:error, "Generation completed but output write failed: #{reason}"}
          end
          
        {:error, reason} ->
          ProgressReporter.error("Generation failed: #{reason}")
          {:error, "AI generation failed: #{reason}"}
      end
      
    rescue
      error ->
        ProgressReporter.error("Generation error: #{Exception.message(error)}")
        {:error, "Generation failed: #{Exception.message(error)}"}
    end
  end
  
  defp execute_explanation(file_path, level, focus) do
    ProgressReporter.start("Generating AI explanation...", show_timer: true)
    
    try do
      ProgressReporter.update("Reading file content")
      {:ok, content} = File.read(file_path)
      
      ProgressReporter.update("Preparing explanation request")
      request = %{
        intent: :explain_codebase,
        description: "CLI code explanation",
        code: content,
        file_path: file_path,
        explanation_level: String.to_atom(level),
        focus_area: String.to_atom(focus),
        context: %{
          cli_context: true
        }
      }
      
      ProgressReporter.update("Generating AI explanation")
      case CodingAssistant.handle_coding_request(request) do
        {:ok, response} ->
          ProgressReporter.complete("Explanation generated successfully!")
          formatted_output = OutputFormatter.format_explanation_result(response, level, focus)
          {:ok, {:ai_explanation, formatted_output, %{file: file_path, level: level, focus: focus}}}
          
        {:error, reason} ->
          ProgressReporter.error("Explanation failed: #{reason}")
          {:error, "AI explanation failed: #{reason}"}
      end
      
    rescue
      error ->
        ProgressReporter.error("Explanation error: #{Exception.message(error)}")
        {:error, "Explanation failed: #{Exception.message(error)}"}
    end
  end
  
  defp execute_refactoring(file_path, refactor_type, apply_changes, show_preview) do
    action = cond do
      apply_changes -> "Applying refactoring"
      show_preview -> "Generating refactoring preview"
      true -> "Analyzing refactoring opportunities"
    end
    
    ProgressReporter.start(action, show_timer: true)
    
    try do
      ProgressReporter.update("Reading file content")
      {:ok, original_content} = File.read(file_path)
      
      ProgressReporter.update("Analyzing code for refactoring")
      request = %{
        intent: :refactor_code,
        description: "CLI refactoring: #{refactor_type}",
        code: original_content,
        file_path: file_path,
        refactor_type: String.to_atom(refactor_type),
        context: %{
          cli_context: true,
          apply_changes: apply_changes,
          show_preview: show_preview
        }
      }
      
      ProgressReporter.update("Generating refactoring suggestions")
      case CodingAssistant.handle_coding_request(request) do
        {:ok, response} ->
          if apply_changes do
            ProgressReporter.update("Applying refactoring changes")
            case apply_refactoring_changes(file_path, original_content, response) do
              :ok ->
                ProgressReporter.complete("Refactoring applied successfully!")
                {:ok, {:ai_refactor, "Refactoring applied to #{file_path}", %{file: file_path, type: refactor_type}}}
                
              {:error, reason} ->
                ProgressReporter.error("Failed to apply changes: #{reason}")
                {:error, "Refactoring generated but application failed: #{reason}"}
            end
          else
            ProgressReporter.complete("Refactoring analysis completed!")
            formatted_output = OutputFormatter.format_refactor_result(response, refactor_type, show_preview)
            {:ok, {:ai_refactor, formatted_output, %{file: file_path, type: refactor_type, preview: show_preview}}}
          end
          
        {:error, reason} ->
          ProgressReporter.error("Refactoring failed: #{reason}")
          {:error, "AI refactoring failed: #{reason}"}
      end
      
    rescue
      error ->
        ProgressReporter.error("Refactoring error: #{Exception.message(error)}")
        {:error, "Refactoring failed: #{Exception.message(error)}"}
    end
  end
  
  defp execute_workflow(template, context_file, description, mode) do
    ProgressReporter.start("Executing AI workflow: #{template}", show_timer: true)
    
    try do
      context_code = if context_file && File.exists?(context_file) do
        ProgressReporter.update("Loading workflow context")
        {:ok, content} = File.read(context_file)
        content
      else
        nil
      end
      
      ProgressReporter.update("Preparing workflow execution")
      workflow_context = %{
        template: template,
        description: description,
        context_code: context_code,
        execution_mode: String.to_atom(mode),
        cli_context: true
      }
      
      ProgressReporter.update("Executing workflow template")
      case WorkflowOrchestrator.execute_template(template, workflow_context) do
        {:ok, workflow_id, workflow_state} ->
          ProgressReporter.complete("Workflow executed successfully!")
          formatted_output = OutputFormatter.format_workflow_result(workflow_state, template)
          {:ok, {:ai_workflow, formatted_output, %{template: template, workflow_id: workflow_id}}}
          
        {:error, reason} ->
          ProgressReporter.error("Workflow failed: #{reason}")
          {:error, "AI workflow failed: #{reason}"}
      end
      
    rescue
      error ->
        ProgressReporter.error("Workflow error: #{Exception.message(error)}")
        {:error, "Workflow failed: #{Exception.message(error)}"}
    end
  end
  
  defp execute_chat(conversation_type, context_dir) do
    ProgressReporter.start("Starting AI chat session...", show_timer: false)
    
    try do
      ProgressReporter.update("Initializing conversation context")
      conversation_context = %{
        type: String.to_atom(conversation_type),
        context_dir: context_dir,
        cli_context: true,
        session_start: DateTime.utc_now()
      }
      
      ProgressReporter.update("Starting conversation manager")
      case ConversationManager.start_conversation(conversation_context) do
        {:ok, conversation_id} ->
          ProgressReporter.complete("Chat session started!")
          
          chat_info = """
          🤖 AI Chat Session Started!
          
          Conversation ID: #{conversation_id}
          Type: #{conversation_type}
          Context: #{context_dir}
          
          To continue this chat session, use:
          aiex shell --mode chat
          
          Or connect via IEx:
          iex> ai_shell()
          """
          
          {:ok, {:ai_chat, chat_info, %{conversation_id: conversation_id, type: conversation_type}}}
          
        {:error, reason} ->
          ProgressReporter.error("Chat initialization failed: #{reason}")
          {:error, "AI chat initialization failed: #{reason}"}
      end
      
    rescue
      error ->
        ProgressReporter.error("Chat error: #{Exception.message(error)}")
        {:error, "Chat session failed: #{Exception.message(error)}"}
    end
  end
  
  # Helper functions
  
  defp write_generated_output(content, nil) do
    IO.puts(content)
    :ok
  end
  defp write_generated_output(content, output_file) do
    case File.write(output_file, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to write to #{output_file}: #{inspect(reason)}"}
    end
  end
  
  defp apply_refactoring_changes(file_path, _original_content, response) do
    case extract_refactored_code(response) do
      {:ok, refactored_code} ->
        File.write(file_path, refactored_code)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp extract_refactored_code(%{artifacts: %{code: code}}), do: {:ok, code}
  defp extract_refactored_code(%{result: %{refactored_code: code}}), do: {:ok, code}
  defp extract_refactored_code(_), do: {:error, "No refactored code found in response"}
end