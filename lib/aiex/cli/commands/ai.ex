defmodule Aiex.CLI.Commands.AI do
  @moduledoc """
  AI command handler for enhanced AI-powered coding assistance.
  
  Integrates with the AI coordinators to provide intelligent command-line
  assistance for code analysis, generation, explanation, refactoring, and workflows.
  """

  @behaviour Aiex.CLI.Commands.CommandBehaviour

  alias Aiex.AI.Coordinators.{CodingAssistant, ConversationManager}
  alias Aiex.AI.WorkflowOrchestrator
  alias Aiex.CLI.Commands.AI.{ProgressReporter, OutputFormatter}
  alias Aiex.LLM.Templates.{TemplateRegistry, TemplateEngine}
  alias Aiex.LLM.ModelCoordinator

  @impl true
  def execute({[:ai], %Optimus.ParseResult{args: args} = parsed}) do
    case Map.keys(args) do
      [:analyze] -> ai_analyze(parsed)
      [:generate] -> ai_generate(parsed)
      [:explain] -> ai_explain(parsed)
      [:refactor] -> ai_refactor(parsed)
      [:workflow] -> ai_workflow(parsed)
      [:chat] -> ai_chat(parsed)
      [:template] -> ai_template(parsed)
      [] -> {:error, "No AI subcommand specified. Use 'aiex help ai' for options."}
      _ -> {:error, "Invalid AI subcommand. Use 'aiex help ai' for options."}
    end
  end

  # AI Analyze Command
  defp ai_analyze(%Optimus.ParseResult{options: options}) do
    file_path = Map.get(options, :file)
    analysis_type = Map.get(options, :type, "quality")
    output_format = Map.get(options, :output, "text")

    case validate_file_path(file_path) do
      {:ok, code_content} ->
        ProgressReporter.start("Analyzing code with AI...")
        
        # Use template system for consistent analysis prompts
        template_variables = %{
          code: code_content,
          language: detect_language(file_path),
          analysis_type: analysis_type,
          file_path: file_path
        }

        case TemplateRegistry.get_template(:analyze_code) do
          {:ok, template} ->
            case TemplateEngine.render(template, template_variables) do
              {:ok, messages} ->
                case ModelCoordinator.request(%{
                  type: :analysis,
                  messages: messages,
                  options: [max_tokens: 1500]
                }) do
                  {:ok, response} ->
                    ProgressReporter.complete("Analysis complete!")
                    formatted_output = format_analysis_response(response, output_format)
                    {:ok, {:ai_analysis, formatted_output}}

                  {:error, reason} ->
                    ProgressReporter.error("Analysis failed: #{reason}")
                    {:error, "AI analysis failed: #{reason}"}
                end

              {:error, reason} ->
                {:error, "Template rendering failed: #{reason}"}
            end

          {:error, _reason} ->
            # Fallback to legacy system if template not available
            fallback_analyze_request(code_content, analysis_type, file_path)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # AI Generate Command
  defp ai_generate(%Optimus.ParseResult{options: options}) do
    generation_type = Map.get(options, :type)
    context_file = Map.get(options, :context)
    requirements = Map.get(options, :requirements)
    output_file = Map.get(options, :output)

    context_code = case context_file do
      nil -> ""
      path -> 
        case File.read(path) do
          {:ok, content} -> content
          {:error, _} -> ""
        end
    end

    ProgressReporter.start("Generating #{generation_type} with AI...")

    # Use template system for code generation
    template_variables = %{
      generation_type: generation_type,
      requirements: requirements,
      context_code: context_code,
      language: "elixir"
    }

    case TemplateRegistry.get_template(:generate_code) do
      {:ok, template} ->
        case TemplateEngine.render(template, template_variables) do
          {:ok, messages} ->
            case ModelCoordinator.request(%{
              type: :generation,
              messages: messages,
              options: [max_tokens: 2500]
            }) do
              {:ok, response} ->
                ProgressReporter.complete("Generation complete!")
                
                # Extract code from response
                generated_code = extract_code_from_response(response.content)
                
                case output_to_destination(generated_code, output_file) do
                  :ok ->
                    {:ok, {:ai_generation, "Code generated successfully", %{code: generated_code}}}
                    
                  {:error, reason} ->
                    {:error, "Failed to write output: #{reason}"}
                end

              {:error, reason} ->
                ProgressReporter.error("Generation failed: #{reason}")
                {:error, "AI generation failed: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Template rendering failed: #{reason}"}
        end

      {:error, _reason} ->
        # Fallback to legacy system if template not available
        fallback_generate_request(generation_type, requirements, context_code, output_file)
    end
  end

  # AI Explain Command
  defp ai_explain(%Optimus.ParseResult{options: options}) do
    file_path = Map.get(options, :file)
    detail_level = Map.get(options, :level, "intermediate")
    focus_area = Map.get(options, :focus, "comprehensive")

    case validate_file_path(file_path) do
      {:ok, code_content} ->
        ProgressReporter.start("Generating AI explanation...")

        # Use template system for consistent prompts
        template_variables = %{
          code: code_content,
          language: detect_language(file_path),
          level: detail_level,
          focus: focus_area
        }

        case TemplateRegistry.get_template(:explain_code) do
          {:ok, template} ->
            case TemplateEngine.render(template, template_variables) do
              {:ok, messages} ->
                case ModelCoordinator.request(%{
                  type: :explanation,
                  messages: messages,
                  options: [max_tokens: 2000]
                }) do
                  {:ok, response} ->
                    ProgressReporter.complete("Explanation generated!")
                    formatted_explanation = format_explanation_response(response, detail_level)
                    {:ok, {:ai_explanation, formatted_explanation}}

                  {:error, reason} ->
                    ProgressReporter.error("Explanation failed: #{reason}")
                    {:error, "AI explanation failed: #{reason}"}
                end

              {:error, reason} ->
                {:error, "Template rendering failed: #{reason}"}
            end

          {:error, _reason} ->
            # Fallback to legacy system if template not available
            fallback_explain_request(code_content, detail_level, focus_area)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # AI Refactor Command
  defp ai_refactor(%Optimus.ParseResult{options: options, flags: flags}) do
    file_path = Map.get(options, :file)
    refactor_type = String.to_atom(Map.get(options, :type, "all"))
    apply_changes = Map.get(flags, :apply, false)
    show_preview = Map.get(flags, :preview, false)

    case validate_file_path(file_path) do
      {:ok, code_content} ->
        ProgressReporter.start("Analyzing code for refactoring opportunities...")

        request = %{
          intent: :refactor_code,
          description: "Refactor code to improve #{refactor_type}",
          code: code_content,
          refactor_type: refactor_type,
          apply: apply_changes,
          preview: show_preview
        }

        case CodingAssistant.handle_coding_request(request) do
          {:ok, response} ->
            ProgressReporter.complete("Refactoring analysis complete!")

            if show_preview do
              preview_output = OutputFormatter.format_refactoring_preview(response)
              {:ok, {:ai_refactor_preview, preview_output}}
            else
              result = if apply_changes do
                case write_refactored_code(file_path, response.artifacts.refactored_code) do
                  :ok -> "Refactoring applied successfully!"
                  {:error, reason} -> "Failed to apply refactoring: #{reason}"
                end
              else
                OutputFormatter.format_refactoring_suggestions(response)
              end

              {:ok, {:ai_refactor, result}}
            end

          {:error, reason} ->
            ProgressReporter.error("Refactoring failed: #{reason}")
            {:error, "AI refactoring failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # AI Workflow Command
  defp ai_workflow(%Optimus.ParseResult{options: options}) do
    template_name = Map.get(options, :template)
    context_file = Map.get(options, :context)
    description = Map.get(options, :description)
    execution_mode = String.to_atom(Map.get(options, :mode, "sequential"))

    context_data = case context_file do
      nil -> %{}
      path ->
        case File.read(path) do
          {:ok, content} -> %{code: content, file_path: path}
          {:error, _} -> %{}
        end
    end

    enhanced_context = Map.merge(context_data, %{
      description: description,
      execution_mode: execution_mode
    })

    ProgressReporter.start("Executing AI workflow: #{template_name}...")

    case WorkflowOrchestrator.execute_template(template_name, enhanced_context) do
      {:ok, workflow_id, workflow_state} ->
        monitor_workflow_progress(workflow_id)
        ProgressReporter.complete("Workflow #{template_name} completed!")
        
        formatted_results = OutputFormatter.format_workflow_results(workflow_state)
        {:ok, {:ai_workflow, "Workflow executed successfully", formatted_results}}

      {:error, reason} ->
        ProgressReporter.error("Workflow failed: #{reason}")
        {:error, "AI workflow failed: #{reason}"}
    end
  end

  # AI Chat Command
  defp ai_chat(%Optimus.ParseResult{options: options}) do
    conversation_type = String.to_atom(Map.get(options, :conversation_type, "coding"))
    context_dir = Map.get(options, :context, ".")

    initial_context = %{
      project_directory: context_dir,
      conversation_type: conversation_type
    }

    IO.puts("🤖 Starting AI Chat Session - #{conversation_type} conversation")
    IO.puts("💡 Type 'exit' or 'quit' to end the session\n")

    case ConversationManager.start_conversation("cli_chat_session", :"#{conversation_type}_conversation", initial_context) do
      {:ok, _conversation_state} ->
        run_interactive_chat_loop()
        {:ok, {:ai_chat, "Chat session ended"}}

      {:error, reason} ->
        {:error, "Failed to start chat session: #{reason}"}
    end
  end

  # AI Template Command
  defp ai_template(%Optimus.ParseResult{args: args} = parsed) do
    case Map.keys(args) do
      [:list] -> template_list(parsed)
      [:test] -> template_test(parsed)
      [] -> {:error, "No template subcommand specified. Use 'aiex help ai template' for options."}
      _ -> {:error, "Invalid template subcommand. Use 'aiex help ai template' for options."}
    end
  end

  defp template_list(%Optimus.ParseResult{options: options}) do
    category = Map.get(options, :category)
    
    case TemplateRegistry.list_templates() do
      {:ok, templates} ->
        filtered_templates = case category do
          nil -> templates
          cat -> Enum.filter(templates, fn {_name, template} -> 
            Map.get(template, :category) == cat 
          end)
        end
        
        IO.puts("📋 Available AI Templates:")
        IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        if Enum.empty?(filtered_templates) do
          IO.puts("No templates found" <> case category do
            nil -> ""
            cat -> " in category '#{cat}'"
          end)
        else
          Enum.each(filtered_templates, fn {name, template} ->
            IO.puts("🔧 #{name}")
            IO.puts("   Description: #{Map.get(template, :description, "No description")}")
            IO.puts("   Category: #{Map.get(template, :category, "unknown")}")
            IO.puts("   Variables: #{inspect(Map.get(template, :variables, []))}")
            IO.puts("")
          end)
        end
        
        {:ok, {:template_list, "Templates listed successfully"}}
        
      {:error, reason} ->
        {:error, "Failed to list templates: #{reason}"}
    end
  end

  defp template_test(%Optimus.ParseResult{options: options}) do
    template_name = Map.get(options, :name) |> String.to_atom()
    variables_json = Map.get(options, :variables, "{}")
    
    case Jason.decode(variables_json) do
      {:ok, variables} ->
        # Convert string keys to atoms
        atom_variables = for {k, v} <- variables, into: %{}, do: {String.to_atom(k), v}
        
        case TemplateRegistry.get_template(template_name) do
          {:ok, template} ->
            IO.puts("🧪 Testing template: #{template_name}")
            IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            case TemplateEngine.render(template, atom_variables) do
              {:ok, messages} ->
                IO.puts("✅ Template rendered successfully!")
                IO.puts("\n📝 Rendered Messages:")
                IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━")
                
                Enum.with_index(messages, 1) |> Enum.each(fn {message, index} ->
                  IO.puts("#{index}. [#{message.role |> to_string() |> String.upcase()}]")
                  IO.puts("   #{String.slice(message.content, 0, 200)}" <> 
                    if String.length(message.content) > 200, do: "...", else: "")
                  IO.puts("")
                end)
                
                {:ok, {:template_test, "Template test completed successfully"}}
                
              {:error, reason} ->
                {:error, "Template rendering failed: #{reason}"}
            end
            
          {:error, reason} ->
            {:error, "Template not found: #{reason}"}
        end
        
      {:error, reason} ->
        {:error, "Invalid JSON in variables: #{reason}"}
    end
  end

  # Helper Functions

  defp validate_file_path(nil) do
    {:error, "File path is required. Use --file to specify the path."}
  end

  defp validate_file_path(file_path) do
    if File.exists?(file_path) do
      case File.read(file_path) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, "Failed to read file: #{reason}"}
      end
    else
      {:error, "File not found: #{file_path}"}
    end
  end

  defp output_to_destination(content, nil) do
    IO.puts(content)
    :ok
  end

  defp output_to_destination(content, output_file) do
    case File.write(output_file, content) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_refactored_code(original_file, refactored_content) do
    backup_file = "#{original_file}.backup"
    
    with :ok <- File.copy(original_file, backup_file),
         :ok <- File.write(original_file, refactored_content) do
      IO.puts("✅ Refactored code applied to #{original_file}")
      IO.puts("💾 Original backed up to #{backup_file}")
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp monitor_workflow_progress(workflow_id) do
    # Poll workflow status and show progress
    monitor_loop(workflow_id, 0)
  end

  defp monitor_loop(workflow_id, checks) do
    case WorkflowOrchestrator.get_workflow_status(workflow_id) do
      {:ok, workflow_state} ->
        case workflow_state.status do
          :completed ->
            :ok
            
          :failed ->
            IO.puts("❌ Workflow failed")
            :error
            
          status when status in [:running, :pending] ->
            if rem(checks, 5) == 0 do  # Update every 5 checks
              ProgressReporter.update("Workflow #{status}... (#{checks * 2}s)")
            end
            
            Process.sleep(2000)  # Wait 2 seconds
            monitor_loop(workflow_id, checks + 1)
            
          _ ->
            :ok
        end

      {:error, _reason} ->
        # Workflow might have completed and been cleaned up
        :ok
    end
  end

  defp run_interactive_chat_loop do
    case IO.gets("🗣️  You: ") do
      input when input in ["exit\n", "quit\n", ":q\n"] ->
        IO.puts("👋 Goodbye!")
        ConversationManager.end_conversation("cli_chat_session")

      input ->
        message = String.trim(input)
        
        case ConversationManager.continue_conversation("cli_chat_session", message) do
          {:ok, response} ->
            IO.puts("🤖 AI: #{response.response}\n")
            
            # Show actions taken if available
            if Map.has_key?(response, :actions_taken) and length(response.actions_taken) > 0 do
              IO.puts("🔧 Actions: #{format_actions(response.actions_taken)}\n")
            end
            
            run_interactive_chat_loop()

          {:error, reason} ->
            IO.puts("❌ Error: #{reason}\n")
            run_interactive_chat_loop()
        end
    end
  end

  defp format_actions(actions) do
    actions
    |> Enum.map(fn action -> action.action end)
    |> Enum.join(", ")
  end

  # Helper functions for template integration

  defp detect_language(file_path) do
    case Path.extname(file_path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".rs" -> "rust"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".py" -> "python"
      ".rb" -> "ruby"
      ".go" -> "go"
      ".java" -> "java"
      ".cpp" -> "cpp"
      ".c" -> "c"
      _ -> "text"
    end
  end

  defp format_analysis_response(response, output_format) do
    case output_format do
      "json" ->
        Jason.encode!(%{
          analysis: response.content,
          timestamp: DateTime.utc_now(),
          provider: response.provider || "unknown"
        })
      
      "markdown" ->
        """
        # Code Analysis Results
        
        **Generated:** #{DateTime.utc_now() |> DateTime.to_string()}
        **Provider:** #{response.provider || "unknown"}
        
        ## Analysis
        
        #{response.content}
        """
      
      _ ->
        response.content
    end
  end

  defp format_explanation_response(response, detail_level) do
    """
    📖 Code Explanation (#{detail_level} level)
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    #{response.content}

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Generated by: #{response.provider || "AI Assistant"}
    """
  end

  defp extract_code_from_response(content) do
    # Try to extract code blocks from markdown
    case Regex.run(~r/```(?:elixir|ex)?\n(.*?)\n```/s, content, capture: :all_but_first) do
      [code] -> String.trim(code)
      nil -> 
        # If no code block found, try to clean up the response
        content
        |> String.trim()
        |> String.replace(~r/^Here's.*?:\s*/m, "")
        |> String.replace(~r/^```\w*\n?/, "")
        |> String.replace(~r/\n?```$/, "")
    end
  end

  # Fallback functions for when templates are not available

  defp fallback_analyze_request(code_content, analysis_type, file_path) do
    # Legacy implementation using CodingAssistant
    request = %{
      intent: :code_review,
      description: "Analyze code for #{analysis_type} insights",
      code: code_content,
      analysis_type: String.to_atom(analysis_type)
    }

    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} ->
        ProgressReporter.complete("Analysis complete!")
        formatted_output = OutputFormatter.format_analysis(response, "text")
        {:ok, {:ai_analysis, formatted_output}}

      {:error, reason} ->
        ProgressReporter.error("Analysis failed: #{reason}")
        {:error, "AI analysis failed: #{reason}"}
    end
  end

  defp fallback_explain_request(code_content, detail_level, focus_area) do
    # Legacy implementation using CodingAssistant
    request = %{
      intent: :explain_codebase,
      description: "Explain code functionality and patterns",
      code: code_content,
      explanation_level: String.to_atom(detail_level),
      focus_area: String.to_atom(focus_area)
    }

    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} ->
        ProgressReporter.complete("Explanation generated!")
        formatted_explanation = OutputFormatter.format_explanation(response)
        {:ok, {:ai_explanation, formatted_explanation}}

      {:error, reason} ->
        ProgressReporter.error("Explanation failed: #{reason}")
        {:error, "AI explanation failed: #{reason}"}
    end
  end

  defp fallback_generate_request(generation_type, requirements, context_code, output_file) do
    # Legacy implementation using CodingAssistant
    request = %{
      intent: :implement_feature,
      description: requirements,
      context_code: context_code,
      generation_type: String.to_atom(generation_type)
    }

    case CodingAssistant.handle_coding_request(request) do
      {:ok, response} ->
        ProgressReporter.complete("Generation complete!")
        
        case output_to_destination(response.artifacts.code, output_file) do
          :ok ->
            {:ok, {:ai_generation, "Code generated successfully", response.artifacts}}
            
          {:error, reason} ->
            {:error, "Failed to write output: #{reason}"}
        end

      {:error, reason} ->
        ProgressReporter.error("Generation failed: #{reason}")
        {:error, "AI generation failed: #{reason}"}
    end
  end
end