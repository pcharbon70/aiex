defmodule Aiex.AI.WorkflowOrchestrator do
  @moduledoc """
  Central workflow orchestrator that coordinates AI engines and assistants
  to execute complex multi-step workflows.
  
  The WorkflowOrchestrator:
  - Manages workflow execution pipelines
  - Coordinates multiple AI engines
  - Handles workflow state and transitions
  - Provides workflow monitoring and metrics
  - Supports parallel and sequential execution
  - Manages error handling and recovery
  """
  
  use GenServer
  require Logger
  
  alias Aiex.AI.Coordinators.{CodingAssistant, ConversationManager}
  alias Aiex.AI.Engines.{
    CodeAnalyzer,
    GenerationEngine,
    ExplanationEngine,
    RefactoringEngine,
    TestGenerator
  }
  alias Aiex.Events.EventBus
  alias Aiex.Context.Manager, as: ContextManager
  
  # Workflow execution modes
  @execution_modes [:sequential, :parallel, :conditional, :pipeline]
  
  # Workflow states
  @workflow_states [:pending, :running, :paused, :completed, :failed, :cancelled]
  
  defstruct [
    :session_id,
    :active_workflows,     # Map of workflow_id -> workflow_state
    :workflow_templates,   # Predefined workflow templates
    :execution_engine,     # Workflow execution engine
    :metrics_collector,    # Workflow metrics
    :error_handler        # Error handling strategy
  ]
  
  ## Public API
  
  @doc """
  Starts the WorkflowOrchestrator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Executes a workflow with the given definition and context.
  
  ## Examples
  
      iex> WorkflowOrchestrator.execute_workflow(%{
      ...>   name: "feature_implementation",
      ...>   steps: [
      ...>     %{engine: :code_analyzer, action: :analyze_requirements},
      ...>     %{engine: :generation_engine, action: :generate_code},
      ...>     %{engine: :test_generator, action: :generate_tests}
      ...>   ]
      ...> }, %{code: "...", requirements: "..."})
      {:ok, "workflow_123", %{status: :running}}
  """
  def execute_workflow(workflow_definition, context \\ %{}) do
    GenServer.call(__MODULE__, {:execute_workflow, workflow_definition, context}, 120_000)
  end
  
  @doc """
  Gets the current status of a workflow.
  """
  def get_workflow_status(workflow_id) do
    GenServer.call(__MODULE__, {:get_workflow_status, workflow_id})
  end
  
  @doc """
  Lists all active workflows.
  """
  def list_active_workflows do
    GenServer.call(__MODULE__, :list_active_workflows)
  end
  
  @doc """
  Pauses a running workflow.
  """
  def pause_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:pause_workflow, workflow_id})
  end
  
  @doc """
  Resumes a paused workflow.
  """
  def resume_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:resume_workflow, workflow_id})
  end
  
  @doc """
  Cancels a workflow.
  """
  def cancel_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:cancel_workflow, workflow_id})
  end
  
  @doc """
  Executes a predefined workflow template.
  """
  def execute_template(template_name, context) do
    GenServer.call(__MODULE__, {:execute_template, template_name, context}, 120_000)
  end
  
  @doc """
  Registers a new workflow template.
  """
  def register_template(template_name, workflow_definition) do
    GenServer.call(__MODULE__, {:register_template, template_name, workflow_definition})
  end
  
  @doc """
  Coordinates multiple engines for a complex task.
  """
  def coordinate_engines(coordination_request) do
    GenServer.call(__MODULE__, {:coordinate_engines, coordination_request}, 90_000)
  end
  
  @doc """
  Gets workflow execution metrics.
  """
  def get_workflow_metrics(workflow_id) do
    GenServer.call(__MODULE__, {:get_workflow_metrics, workflow_id})
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    state = %__MODULE__{
      session_id: session_id,
      active_workflows: %{},
      workflow_templates: initialize_workflow_templates(),
      execution_engine: initialize_execution_engine(),
      metrics_collector: %{},
      error_handler: initialize_error_handler()
    }
    
    Logger.info("WorkflowOrchestrator started with session_id: #{session_id}")
    
    EventBus.publish("ai.workflow_orchestrator.started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:execute_workflow, workflow_definition, context}, _from, state) do
    case start_workflow_execution(workflow_definition, context, state) do
      {:ok, workflow_id, workflow_state, updated_state} ->
        {:reply, {:ok, workflow_id, workflow_state}, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_workflow_status, workflow_id}, _from, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil -> {:reply, {:error, :workflow_not_found}, state}
      workflow -> {:reply, {:ok, workflow}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:list_active_workflows, _from, state) do
    workflows = state.active_workflows
    |> Enum.map(fn {id, workflow} ->
      %{
        workflow_id: id,
        name: workflow.name,
        status: workflow.status,
        started_at: workflow.started_at,
        progress: calculate_workflow_progress(workflow)
      }
    end)
    
    {:reply, {:ok, workflows}, state}
  end
  
  @impl GenServer
  def handle_call({:pause_workflow, workflow_id}, _from, state) do
    case update_workflow_status(workflow_id, :paused, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:resume_workflow, workflow_id}, _from, state) do
    case update_workflow_status(workflow_id, :running, state) do
      {:ok, updated_state} ->
        # Continue execution
        continue_workflow_execution(workflow_id, updated_state)
        {:reply, :ok, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:cancel_workflow, workflow_id}, _from, state) do
    case cancel_workflow_execution(workflow_id, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:execute_template, template_name, context}, _from, state) do
    case Map.get(state.workflow_templates, template_name) do
      nil ->
        {:reply, {:error, :template_not_found}, state}
        
      workflow_definition ->
        case start_workflow_execution(workflow_definition, context, state) do
          {:ok, workflow_id, workflow_state, updated_state} ->
            {:reply, {:ok, workflow_id, workflow_state}, updated_state}
            
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl GenServer
  def handle_call({:register_template, template_name, workflow_definition}, _from, state) do
    updated_templates = Map.put(state.workflow_templates, template_name, workflow_definition)
    updated_state = %{state | workflow_templates: updated_templates}
    
    {:reply, :ok, updated_state}
  end
  
  @impl GenServer
  def handle_call({:coordinate_engines, coordination_request}, _from, state) do
    case execute_engine_coordination(coordination_request, state) do
      {:ok, coordination_result} ->
        {:reply, {:ok, coordination_result}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_workflow_metrics, workflow_id}, _from, state) do
    case Map.get(state.metrics_collector, workflow_id) do
      nil -> {:reply, {:error, :metrics_not_found}, state}
      metrics -> {:reply, {:ok, metrics}, state}
    end
  end
  
  ## Private Implementation
  
  defp start_workflow_execution(workflow_definition, context, state) do
    workflow_id = generate_workflow_id()
    
    workflow_state = %{
      workflow_id: workflow_id,
      name: Map.get(workflow_definition, :name, "unnamed_workflow"),
      definition: workflow_definition,
      context: context,
      status: :running,
      started_at: DateTime.utc_now(),
      current_step: 0,
      steps: Map.get(workflow_definition, :steps, []),
      execution_mode: Map.get(workflow_definition, :execution_mode, :sequential),
      results: %{},
      errors: [],
      metadata: %{}
    }
    
    # Start execution
    case execute_workflow_steps(workflow_state, state) do
      {:ok, updated_workflow_state} ->
        updated_workflows = Map.put(state.active_workflows, workflow_id, updated_workflow_state)
        updated_state = %{state | active_workflows: updated_workflows}
        
        # Initialize metrics
        metrics = initialize_workflow_metrics(workflow_id, workflow_definition)
        updated_metrics = Map.put(state.metrics_collector, workflow_id, metrics)
        final_state = %{updated_state | metrics_collector: updated_metrics}
        
        EventBus.publish("ai.workflow_orchestrator.workflow_started", %{
          workflow_id: workflow_id,
          workflow_name: workflow_state.name,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, workflow_id, updated_workflow_state, final_state}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp execute_workflow_steps(workflow_state, orchestrator_state) do
    case workflow_state.execution_mode do
      :sequential -> execute_sequential_workflow(workflow_state, orchestrator_state)
      :parallel -> execute_parallel_workflow(workflow_state, orchestrator_state)
      :conditional -> execute_conditional_workflow(workflow_state, orchestrator_state)
      :pipeline -> execute_pipeline_workflow(workflow_state, orchestrator_state)
      _ -> {:error, "Unknown execution mode: #{workflow_state.execution_mode}"}
    end
  end
  
  defp execute_sequential_workflow(workflow_state, orchestrator_state) do
    steps = workflow_state.steps
    
    {final_state, final_results} = Enum.reduce_while(steps, {workflow_state, %{}}, fn step, {current_state, results} ->
      case execute_workflow_step(step, current_state, results, orchestrator_state) do
        {:ok, step_result} ->
          updated_results = Map.put(results, step_key(step), step_result)
          updated_state = %{current_state | 
            current_step: current_state.current_step + 1,
            results: updated_results
          }
          {:cont, {updated_state, updated_results}}
          
        {:error, reason} ->
          error_state = %{current_state | 
            status: :failed,
            errors: [reason | current_state.errors]
          }
          {:halt, {error_state, results}}
      end
    end)
    
    final_workflow_state = if final_state.status == :failed do
      final_state
    else
      %{final_state | status: :completed, results: final_results}
    end
    
    {:ok, final_workflow_state}
  end
  
  defp execute_parallel_workflow(workflow_state, orchestrator_state) do
    steps = workflow_state.steps
    
    # Execute all steps in parallel
    tasks = Enum.map(steps, fn step ->
      Task.async(fn ->
        execute_workflow_step(step, workflow_state, %{}, orchestrator_state)
      end)
    end)
    
    # Wait for all tasks to complete
    results = Task.await_many(tasks, 300_000)  # 5 minutes timeout
    
    # Collect results and errors
    {step_results, errors} = Enum.zip(steps, results)
    |> Enum.reduce({%{}, []}, fn {step, result}, {acc_results, acc_errors} ->
      case result do
        {:ok, step_result} ->
          {Map.put(acc_results, step_key(step), step_result), acc_errors}
          
        {:error, reason} ->
          {acc_results, [reason | acc_errors]}
      end
    end)
    
    final_status = if length(errors) > 0, do: :failed, else: :completed
    
    final_workflow_state = %{workflow_state |
      status: final_status,
      results: step_results,
      errors: errors
    }
    
    {:ok, final_workflow_state}
  end
  
  defp execute_conditional_workflow(workflow_state, orchestrator_state) do
    # Execute steps based on conditions
    execute_sequential_workflow(workflow_state, orchestrator_state)
  end
  
  defp execute_pipeline_workflow(workflow_state, orchestrator_state) do
    # Pipeline execution where output of one step feeds to next
    steps = workflow_state.steps
    
    {final_state, pipeline_result} = Enum.reduce_while(steps, {workflow_state, workflow_state.context}, 
      fn step, {current_state, pipeline_data} ->
        case execute_workflow_step(step, current_state, pipeline_data, orchestrator_state) do
          {:ok, step_result} ->
            # Use step result as input for next step
            updated_state = %{current_state | current_step: current_state.current_step + 1}
            {:cont, {updated_state, step_result}}
            
          {:error, reason} ->
            error_state = %{current_state | 
              status: :failed,
              errors: [reason | current_state.errors]
            }
            {:halt, {error_state, pipeline_data}}
        end
      end)
    
    final_workflow_state = if final_state.status == :failed do
      final_state
    else
      %{final_state | status: :completed, results: %{pipeline_output: pipeline_result}}
    end
    
    {:ok, final_workflow_state}
  end
  
  defp execute_workflow_step(step, workflow_state, context_data, orchestrator_state) do
    engine = Map.get(step, :engine)
    action = Map.get(step, :action)
    step_params = Map.get(step, :params, %{})
    
    # Prepare step context
    step_context = Map.merge(workflow_state.context, %{
      workflow_id: workflow_state.workflow_id,
      step_data: context_data,
      step_params: step_params
    })
    
    # Execute step based on engine
    case engine do
      :coding_assistant -> execute_coding_assistant_step(action, step_context, orchestrator_state)
      :conversation_manager -> execute_conversation_manager_step(action, step_context, orchestrator_state)
      :code_analyzer -> execute_code_analyzer_step(action, step_context, orchestrator_state)
      :generation_engine -> execute_generation_engine_step(action, step_context, orchestrator_state)
      :explanation_engine -> execute_explanation_engine_step(action, step_context, orchestrator_state)
      :refactoring_engine -> execute_refactoring_engine_step(action, step_context, orchestrator_state)
      :test_generator -> execute_test_generator_step(action, step_context, orchestrator_state)
      _ -> {:error, "Unknown engine: #{engine}"}
    end
  end
  
  defp execute_coding_assistant_step(action, context, _orchestrator_state) do
    request = %{
      intent: action,
      description: Map.get(context, :description, "Workflow step execution"),
      code: Map.get(context, :code),
      context_code: Map.get(context, :context_code)
    }
    
    case CodingAssistant.handle_coding_request(request, context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_conversation_manager_step(action, context, _orchestrator_state) do
    case action do
      :start_conversation ->
        conversation_id = Map.get(context, :conversation_id, generate_conversation_id())
        conversation_type = Map.get(context, :conversation_type, :general_conversation)
        ConversationManager.start_conversation(conversation_id, conversation_type, context)
        
      :continue_conversation ->
        conversation_id = Map.get(context, :conversation_id)
        message = Map.get(context, :message, "")
        ConversationManager.continue_conversation(conversation_id, message, context)
        
      _ ->
        {:error, "Unknown conversation manager action: #{action}"}
    end
  end
  
  defp execute_code_analyzer_step(action, context, _orchestrator_state) do
    code = Map.get(context, :code, "")
    analysis_type = Map.get(context, :analysis_type, action)
    
    case CodeAnalyzer.analyze_code(code, analysis_type) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_generation_engine_step(action, context, _orchestrator_state) do
    requirements = Map.get(context, :requirements, [])
    generation_type = Map.get(context, :generation_type, action)
    options = Map.get(context, :step_params, [])
    
    case GenerationEngine.generate_code(requirements, generation_type, options) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_explanation_engine_step(action, context, _orchestrator_state) do
    code = Map.get(context, :code, "")
    explanation_type = Map.get(context, :explanation_type, action)
    audience_level = Map.get(context, :audience_level, :intermediate)
    options = Map.get(context, :step_params, [])
    
    case ExplanationEngine.explain_code(code, explanation_type, audience_level, options) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_refactoring_engine_step(action, context, _orchestrator_state) do
    code = Map.get(context, :code, "")
    refactoring_type = Map.get(context, :refactoring_type, action)
    options = Map.get(context, :step_params, [])
    
    case RefactoringEngine.suggest_refactoring(code, refactoring_type, options) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_test_generator_step(action, context, _orchestrator_state) do
    code = Map.get(context, :code, "")
    test_type = Map.get(context, :test_type, action)
    options = Map.get(context, :step_params, [])
    
    case TestGenerator.generate_tests(code, test_type, options) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_engine_coordination(coordination_request, _state) do
    engines = Map.get(coordination_request, :engines, [])
    coordination_type = Map.get(coordination_request, :type, :parallel)
    context = Map.get(coordination_request, :context, %{})
    
    case coordination_type do
      :parallel ->
        # Execute all engines in parallel
        tasks = Enum.map(engines, fn engine_config ->
          Task.async(fn ->
            execute_engine_coordination_step(engine_config, context)
          end)
        end)
        
        results = Task.await_many(tasks, 180_000)  # 3 minutes timeout
        {:ok, %{coordination_type: :parallel, results: results}}
        
      :sequential ->
        # Execute engines sequentially
        results = Enum.map(engines, fn engine_config ->
          execute_engine_coordination_step(engine_config, context)
        end)
        {:ok, %{coordination_type: :sequential, results: results}}
        
      _ ->
        {:error, "Unknown coordination type: #{coordination_type}"}
    end
  end
  
  defp execute_engine_coordination_step(engine_config, context) do
    engine = Map.get(engine_config, :engine)
    request = Map.get(engine_config, :request, %{})
    merged_context = Map.merge(context, Map.get(engine_config, :context, %{}))
    
    case engine do
      :code_analyzer ->
        code = Map.get(request, :code, "")
        analysis_type = Map.get(request, :type, :structure_analysis)
        CodeAnalyzer.analyze_code(code, analysis_type)
        
      :test_generator ->
        code = Map.get(request, :code, "")
        test_type = Map.get(request, :type, :unit_tests)
        TestGenerator.generate_tests(code, test_type)
        
      _ ->
        {:error, "Engine coordination not implemented for: #{engine}"}
    end
  end
  
  defp step_key(step) do
    Map.get(step, :name, "step_#{Map.get(step, :engine)}_#{Map.get(step, :action)}")
  end
  
  defp update_workflow_status(workflow_id, new_status, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        {:error, :workflow_not_found}
        
      workflow ->
        updated_workflow = %{workflow | status: new_status}
        updated_workflows = Map.put(state.active_workflows, workflow_id, updated_workflow)
        updated_state = %{state | active_workflows: updated_workflows}
        
        EventBus.publish("ai.workflow_orchestrator.workflow_status_changed", %{
          workflow_id: workflow_id,
          old_status: workflow.status,
          new_status: new_status,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, updated_state}
    end
  end
  
  defp cancel_workflow_execution(workflow_id, state) do
    case update_workflow_status(workflow_id, :cancelled, state) do
      {:ok, updated_state} ->
        # Remove from active workflows
        final_workflows = Map.delete(updated_state.active_workflows, workflow_id)
        final_state = %{updated_state | active_workflows: final_workflows}
        
        {:ok, final_state}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp continue_workflow_execution(workflow_id, state) do
    # Continue execution for paused workflows
    # This would involve resuming from the current step
    case Map.get(state.active_workflows, workflow_id) do
      nil -> :ok
      workflow ->
        # Resume execution logic would go here
        Logger.info("Resuming workflow execution for #{workflow_id}")
        :ok
    end
  end
  
  defp calculate_workflow_progress(workflow) do
    total_steps = length(workflow.steps)
    if total_steps == 0 do
      100
    else
      completed_steps = workflow.current_step
      Float.round(completed_steps / total_steps * 100, 1)
    end
  end
  
  defp initialize_workflow_templates do
    %{
      "feature_implementation" => %{
        name: "Feature Implementation",
        execution_mode: :sequential,
        steps: [
          %{engine: :code_analyzer, action: :analyze_requirements, name: "analyze_requirements"},
          %{engine: :generation_engine, action: :generate_implementation, name: "generate_code"},
          %{engine: :test_generator, action: :unit_tests, name: "generate_tests"},
          %{engine: :explanation_engine, action: :comprehensive, name: "generate_docs"}
        ]
      },
      
      "bug_fix_workflow" => %{
        name: "Bug Fix Workflow",
        execution_mode: :sequential,
        steps: [
          %{engine: :code_analyzer, action: :quality_analysis, name: "analyze_bug"},
          %{engine: :refactoring_engine, action: :fix_issues, name: "suggest_fix"},
          %{engine: :generation_engine, action: :bug_fix, name: "implement_fix"},
          %{engine: :test_generator, action: :regression_tests, name: "generate_regression_tests"}
        ]
      },
      
      "code_review_workflow" => %{
        name: "Code Review Workflow",
        execution_mode: :parallel,
        steps: [
          %{engine: :code_analyzer, action: :quality_analysis, name: "quality_analysis"},
          %{engine: :refactoring_engine, action: :all, name: "refactoring_suggestions"},
          %{engine: :test_generator, action: :test_suite_analysis, name: "test_coverage_analysis"}
        ]
      }
    }
  end
  
  defp initialize_execution_engine do
    %{
      max_concurrent_workflows: 10,
      step_timeout: 300_000,  # 5 minutes
      workflow_timeout: 1_800_000,  # 30 minutes
      retry_attempts: 3
    }
  end
  
  defp initialize_error_handler do
    %{
      retry_strategy: :exponential_backoff,
      max_retries: 3,
      fallback_strategy: :partial_completion
    }
  end
  
  defp initialize_workflow_metrics(workflow_id, workflow_definition) do
    %{
      workflow_id: workflow_id,
      started_at: DateTime.utc_now(),
      total_steps: length(Map.get(workflow_definition, :steps, [])),
      completed_steps: 0,
      failed_steps: 0,
      execution_time_ms: 0,
      step_timings: %{}
    }
  end
  
  defp generate_workflow_id do
    "workflow_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
  
  defp generate_conversation_id do
    "conv_" <> Base.encode16(:crypto.strong_rand_bytes(6))
  end
  
  defp generate_session_id do
    "workflow_orchestrator_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
end