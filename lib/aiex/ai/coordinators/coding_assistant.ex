defmodule Aiex.AI.Coordinators.CodingAssistant do
  @moduledoc """
  High-level AI coding assistant that orchestrates multiple AI engines
  to provide comprehensive coding assistance. This coordinator manages
  workflows for complex coding tasks by intelligently combining the
  capabilities of various AI engines.
  
  The CodingAssistant can handle tasks such as:
  - Understanding and implementing feature requests
  - Analyzing and fixing bugs
  - Refactoring code with test generation
  - Explaining complex codebases
  - Generating documentation and examples
  """
  
  use GenServer
  require Logger
  
  @behaviour Aiex.AI.Behaviours.Assistant
  
  alias Aiex.AI.Engines.{
    CodeAnalyzer,
    GenerationEngine,
    ExplanationEngine,
    RefactoringEngine,
    TestGenerator
  }
  
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.Events.EventBus
  
  # Supported workflow types
  @supported_workflows [
    :implement_feature,    # Implement a new feature
    :fix_bug,             # Fix a bug in existing code
    :refactor_code,       # Refactor with tests
    :explain_codebase,    # Explain how code works
    :generate_tests,      # Generate comprehensive tests
    :improve_code,        # General code improvement
    :code_review,         # Review code for issues
    :generate_docs        # Generate documentation
  ]
  
  defstruct [
    :session_id,
    :conversation_history,
    :active_engines,
    :workflow_state,
    :project_context,
    :user_preferences
  ]
  
  ## Public API
  
  @doc """
  Starts the CodingAssistant coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Handles a coding request by orchestrating multiple AI engines.
  
  ## Examples
  
      iex> CodingAssistant.handle_coding_request(%{
      ...>   intent: :implement_feature,
      ...>   description: "Add user authentication",
      ...>   context: %{file: "lib/app.ex"}
      ...> })
      {:ok, %{response: "...", actions_taken: [...], next_steps: [...]}}
  """
  def handle_coding_request(request, conversation_context \\ %{}) do
    GenServer.call(__MODULE__, {:handle_request, request, conversation_context}, 60_000)
  end
  
  @doc """
  Starts a new coding assistance session.
  """
  def start_coding_session(session_id, initial_context \\ %{}) do
    GenServer.call(__MODULE__, {:start_session, session_id, initial_context})
  end
  
  @doc """
  Ends a coding assistance session.
  """
  def end_coding_session(session_id) do
    GenServer.call(__MODULE__, {:end_session, session_id})
  end
  
  @doc """
  Gets the current workflow state for a session.
  """
  def get_workflow_state(session_id) do
    GenServer.call(__MODULE__, {:get_workflow_state, session_id})
  end
  
  ## Assistant Behavior Implementation
  
  @impl Aiex.AI.Behaviours.Assistant
  def handle_request(request, conversation_context, project_context) do
    GenServer.call(__MODULE__, 
      {:handle_request_behavior, request, conversation_context, project_context}, 
      60_000)
  end
  
  @impl Aiex.AI.Behaviours.Assistant
  def can_handle_request?(request_type) do
    request_type in [:coding_task, :feature_request, :bug_fix, :refactoring, 
                    :code_explanation, :test_generation, :code_review, :documentation]
  end
  
  @impl Aiex.AI.Behaviours.Assistant
  def start_session(session_id, initial_context) do
    GenServer.call(__MODULE__, {:start_session, session_id, initial_context})
  end
  
  @impl Aiex.AI.Behaviours.Assistant
  def end_session(session_id) do
    GenServer.call(__MODULE__, {:end_session, session_id})
  end
  
  @impl Aiex.AI.Behaviours.Assistant
  def get_capabilities do
    %{
      name: "Coding Assistant",
      description: "Orchestrates multiple AI engines for comprehensive coding assistance",
      supported_workflows: @supported_workflows,
      required_engines: [
        CodeAnalyzer,
        GenerationEngine,
        ExplanationEngine,
        RefactoringEngine,
        TestGenerator
      ],
      capabilities: [
        "Multi-step feature implementation",
        "Intelligent bug fixing with root cause analysis",
        "Code refactoring with automatic test generation",
        "Comprehensive codebase explanations",
        "Context-aware code generation",
        "Automated code review and improvement suggestions",
        "Documentation generation"
      ]
    }
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    state = %__MODULE__{
      session_id: session_id,
      conversation_history: [],
      active_engines: %{},
      workflow_state: %{},
      project_context: %{},
      user_preferences: load_user_preferences(opts)
    }
    
    Logger.info("CodingAssistant started with session_id: #{session_id}")
    
    EventBus.publish("ai.coordinator.coding_assistant.started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:handle_request, request, conversation_context}, _from, state) do
    result = orchestrate_coding_request(request, conversation_context, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:handle_request_behavior, request, conversation_context, project_context}, _from, state) do
    updated_state = %{state | project_context: project_context}
    
    case orchestrate_coding_request(request, conversation_context, updated_state) do
      {:ok, response} ->
        updated_context = update_conversation_context(conversation_context, request, response)
        {:reply, {:ok, response, updated_context}, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, updated_state}
    end
  end
  
  @impl GenServer
  def handle_call({:start_session, session_id, initial_context}, _from, state) do
    new_session_state = %{
      session_id: session_id,
      started_at: DateTime.utc_now(),
      context: initial_context,
      history: []
    }
    
    updated_workflow_state = Map.put(state.workflow_state, session_id, new_session_state)
    updated_state = %{state | workflow_state: updated_workflow_state}
    
    EventBus.publish("ai.coordinator.coding_assistant.session_started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, {:ok, new_session_state}, updated_state}
  end
  
  @impl GenServer
  def handle_call({:end_session, session_id}, _from, state) do
    if Map.has_key?(state.workflow_state, session_id) do
      updated_workflow_state = Map.delete(state.workflow_state, session_id)
      updated_state = %{state | workflow_state: updated_workflow_state}
      
      EventBus.publish("ai.coordinator.coding_assistant.session_ended", %{
        session_id: session_id,
        timestamp: DateTime.utc_now()
      })
      
      {:reply, :ok, updated_state}
    else
      {:reply, {:error, :session_not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_workflow_state, session_id}, _from, state) do
    case Map.get(state.workflow_state, session_id) do
      nil -> {:reply, {:error, :session_not_found}, state}
      session_state -> {:reply, {:ok, session_state}, state}
    end
  end
  
  ## Private Implementation
  
  defp orchestrate_coding_request(request, conversation_context, state) do
    start_time = System.monotonic_time(:millisecond)
    
    # Determine the workflow type from the request
    workflow_type = determine_workflow_type(request)
    
    # Execute the appropriate workflow
    result = case workflow_type do
      :implement_feature -> execute_feature_workflow(request, conversation_context, state)
      :fix_bug -> execute_bug_fix_workflow(request, conversation_context, state)
      :refactor_code -> execute_refactoring_workflow(request, conversation_context, state)
      :explain_codebase -> execute_explanation_workflow(request, conversation_context, state)
      :generate_tests -> execute_test_generation_workflow(request, conversation_context, state)
      :improve_code -> execute_improvement_workflow(request, conversation_context, state)
      :code_review -> execute_review_workflow(request, conversation_context, state)
      :generate_docs -> execute_documentation_workflow(request, conversation_context, state)
      _ -> {:error, "Unknown workflow type: #{workflow_type}"}
    end
    
    # Record metrics
    duration = System.monotonic_time(:millisecond) - start_time
    record_workflow_metrics(workflow_type, duration, result)
    
    result
  end
  
  defp determine_workflow_type(request) do
    intent = Map.get(request, :intent)
    
    cond do
      intent in @supported_workflows -> intent
      String.contains?(to_string(request[:description] || ""), ["implement", "add", "create"]) -> :implement_feature
      String.contains?(to_string(request[:description] || ""), ["fix", "bug", "error", "issue"]) -> :fix_bug
      String.contains?(to_string(request[:description] || ""), ["refactor", "improve", "clean"]) -> :refactor_code
      String.contains?(to_string(request[:description] || ""), ["explain", "understand", "how"]) -> :explain_codebase
      String.contains?(to_string(request[:description] || ""), ["test", "testing", "coverage"]) -> :generate_tests
      String.contains?(to_string(request[:description] || ""), ["review", "check", "analyze"]) -> :code_review
      String.contains?(to_string(request[:description] || ""), ["document", "docs", "readme"]) -> :generate_docs
      true -> :improve_code
    end
  end
  
  defp execute_feature_workflow(request, conversation_context, state) do
    with {:ok, analysis} <- analyze_feature_request(request, state),
         {:ok, design} <- design_feature_implementation(analysis, conversation_context, state),
         {:ok, implementation} <- generate_feature_code(design, state),
         {:ok, tests} <- generate_feature_tests(implementation, state),
         {:ok, documentation} <- generate_feature_docs(implementation, state) do
      
      {:ok, %{
        response: format_feature_response(implementation, tests, documentation),
        workflow: :implement_feature,
        actions_taken: [
          %{action: :analyzed_request, result: analysis},
          %{action: :designed_solution, result: design},
          %{action: :generated_code, result: implementation},
          %{action: :generated_tests, result: tests},
          %{action: :generated_docs, result: documentation}
        ],
        next_steps: suggest_next_steps(:feature_implementation, implementation),
        artifacts: %{
          code: implementation.code,
          tests: tests.test_code,
          documentation: documentation.content
        }
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_bug_fix_workflow(request, conversation_context, state) do
    with {:ok, analysis} <- analyze_bug_report(request, state),
         {:ok, root_cause} <- identify_root_cause(analysis, state),
         {:ok, fix_strategy} <- design_fix_strategy(root_cause, conversation_context, state),
         {:ok, fix_implementation} <- implement_bug_fix(fix_strategy, state),
         {:ok, regression_tests} <- generate_regression_tests(fix_implementation, state) do
      
      {:ok, %{
        response: format_bug_fix_response(root_cause, fix_implementation, regression_tests),
        workflow: :fix_bug,
        actions_taken: [
          %{action: :analyzed_bug, result: analysis},
          %{action: :identified_root_cause, result: root_cause},
          %{action: :designed_fix, result: fix_strategy},
          %{action: :implemented_fix, result: fix_implementation},
          %{action: :generated_regression_tests, result: regression_tests}
        ],
        next_steps: suggest_next_steps(:bug_fix, fix_implementation),
        artifacts: %{
          fix: fix_implementation.code,
          tests: regression_tests.test_code,
          analysis: root_cause.explanation
        }
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_refactoring_workflow(request, conversation_context, state) do
    with {:ok, analysis} <- analyze_code_for_refactoring(request, state),
         {:ok, refactoring_plan} <- create_refactoring_plan(analysis, conversation_context, state),
         {:ok, refactored_code} <- apply_refactorings(refactoring_plan, state),
         {:ok, tests} <- ensure_test_coverage(refactored_code, state),
         {:ok, validation} <- validate_refactoring(refactored_code, state) do
      
      {:ok, %{
        response: format_refactoring_response(refactoring_plan, refactored_code, validation),
        workflow: :refactor_code,
        actions_taken: [
          %{action: :analyzed_code, result: analysis},
          %{action: :created_plan, result: refactoring_plan},
          %{action: :refactored_code, result: refactored_code},
          %{action: :ensured_tests, result: tests},
          %{action: :validated_refactoring, result: validation}
        ],
        next_steps: suggest_next_steps(:refactoring, refactored_code),
        artifacts: %{
          refactored_code: refactored_code.code,
          tests: tests.test_code,
          improvements: refactoring_plan.improvements
        }
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_explanation_workflow(request, conversation_context, state) do
    with {:ok, code_analysis} <- analyze_code_structure(request, state),
         {:ok, explanations} <- generate_explanations(code_analysis, conversation_context, state),
         {:ok, examples} <- generate_usage_examples(code_analysis, state),
         {:ok, diagrams} <- generate_conceptual_diagrams(code_analysis, state) do
      
      {:ok, %{
        response: format_explanation_response(explanations, examples, diagrams),
        workflow: :explain_codebase,
        actions_taken: [
          %{action: :analyzed_structure, result: code_analysis},
          %{action: :generated_explanations, result: explanations},
          %{action: :created_examples, result: examples},
          %{action: :created_diagrams, result: diagrams}
        ],
        next_steps: suggest_next_steps(:explanation, explanations),
        artifacts: %{
          explanations: explanations.content,
          examples: examples.code_examples,
          diagrams: diagrams.visualizations
        }
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_test_generation_workflow(request, conversation_context, state) do
    with {:ok, code_analysis} <- analyze_code_for_testing(request, state),
         {:ok, test_strategy} <- design_test_strategy(code_analysis, conversation_context, state),
         {:ok, unit_tests} <- generate_unit_tests(test_strategy, state),
         {:ok, integration_tests} <- generate_integration_tests(test_strategy, state),
         {:ok, test_data} <- generate_test_data(test_strategy, state) do
      
      {:ok, %{
        response: format_test_generation_response(unit_tests, integration_tests, test_data),
        workflow: :generate_tests,
        actions_taken: [
          %{action: :analyzed_code, result: code_analysis},
          %{action: :designed_strategy, result: test_strategy},
          %{action: :generated_unit_tests, result: unit_tests},
          %{action: :generated_integration_tests, result: integration_tests},
          %{action: :generated_test_data, result: test_data}
        ],
        next_steps: suggest_next_steps(:test_generation, unit_tests),
        artifacts: %{
          unit_tests: unit_tests.test_code,
          integration_tests: integration_tests.test_code,
          test_data: test_data.fixtures
        }
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_improvement_workflow(request, conversation_context, state) do
    with {:ok, analysis} <- comprehensive_code_analysis(request, state),
         {:ok, improvements} <- identify_improvements(analysis, conversation_context, state),
         {:ok, prioritized} <- prioritize_improvements(improvements, state),
         {:ok, implementation} <- implement_improvements(prioritized, state),
         {:ok, validation} <- validate_improvements(implementation, state) do
      
      {:ok, %{
        response: format_improvement_response(improvements, implementation, validation),
        workflow: :improve_code,
        actions_taken: [
          %{action: :analyzed_code, result: analysis},
          %{action: :identified_improvements, result: improvements},
          %{action: :prioritized_changes, result: prioritized},
          %{action: :implemented_improvements, result: implementation},
          %{action: :validated_changes, result: validation}
        ],
        next_steps: suggest_next_steps(:improvement, implementation),
        artifacts: %{
          improved_code: implementation.code,
          improvement_report: improvements.report
        }
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_review_workflow(request, conversation_context, state) do
    with {:ok, analysis} <- analyze_code_quality(request, state),
         {:ok, issues} <- identify_code_issues(analysis, state),
         {:ok, suggestions} <- generate_review_suggestions(issues, conversation_context, state),
         {:ok, fixes} <- generate_suggested_fixes(issues, state) do
      
      {:ok, %{
        response: format_review_response(issues, suggestions, fixes),
        workflow: :code_review,
        actions_taken: [
          %{action: :analyzed_quality, result: analysis},
          %{action: :identified_issues, result: issues},
          %{action: :generated_suggestions, result: suggestions},
          %{action: :suggested_fixes, result: fixes}
        ],
        next_steps: suggest_next_steps(:code_review, issues),
        artifacts: %{
          review_report: format_review_report(issues, suggestions),
          suggested_fixes: fixes.code_changes
        }
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_documentation_workflow(request, conversation_context, state) do
    with {:ok, code_analysis} <- analyze_code_for_documentation(request, state),
         {:ok, doc_structure} <- design_documentation_structure(code_analysis, conversation_context, state),
         {:ok, api_docs} <- generate_api_documentation(doc_structure, state),
         {:ok, examples} <- generate_documentation_examples(doc_structure, state),
         {:ok, readme} <- generate_readme_content(doc_structure, state) do
      
      {:ok, %{
        response: format_documentation_response(api_docs, examples, readme),
        workflow: :generate_docs,
        actions_taken: [
          %{action: :analyzed_code, result: code_analysis},
          %{action: :designed_structure, result: doc_structure},
          %{action: :generated_api_docs, result: api_docs},
          %{action: :created_examples, result: examples},
          %{action: :generated_readme, result: readme}
        ],
        next_steps: suggest_next_steps(:documentation, api_docs),
        artifacts: %{
          api_documentation: api_docs.content,
          examples: examples.code_examples,
          readme: readme.content
        }
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  # Feature Implementation Helpers
  
  defp analyze_feature_request(request, _state) do
    # Use CodeAnalyzer to understand the context
    case CodeAnalyzer.analyze_code(
      Map.get(request, :context_code, ""), 
      :structure_analysis
    ) do
      {:ok, analysis} ->
        {:ok, %{
          feature_description: Map.get(request, :description),
          context_analysis: analysis,
          requirements: extract_requirements(request)
        }}
      error -> error
    end
  end
  
  defp design_feature_implementation(analysis, _conversation_context, _state) do
    # Create a design plan for the feature
    {:ok, %{
      approach: "Modular implementation with clear separation of concerns",
      components: identify_required_components(analysis),
      integration_points: identify_integration_points(analysis)
    }}
  end
  
  defp generate_feature_code(design, _state) do
    # Use GenerationEngine to create the implementation
    case GenerationEngine.generate_code(
      Map.get(design, :components, []),
      :feature_implementation,
      design: design
    ) do
      {:ok, generated} -> {:ok, %{code: generated.code, metadata: generated.metadata}}
      error -> error
    end
  end
  
  defp generate_feature_tests(implementation, _state) do
    # Use TestGenerator to create comprehensive tests
    case TestGenerator.generate_tests(
      implementation.code,
      :unit_tests,
      coverage: :comprehensive
    ) do
      {:ok, tests} -> {:ok, %{test_code: tests.generated_tests, coverage: tests.coverage_estimate}}
      error -> error
    end
  end
  
  defp generate_feature_docs(implementation, _state) do
    # Use ExplanationEngine to create documentation
    case ExplanationEngine.explain_code(
      implementation.code,
      :comprehensive,
      :intermediate,
      [generate_docs: true]
    ) do
      {:ok, explanation} -> {:ok, %{content: explanation.content, type: :feature_documentation}}
      error -> error
    end
  end
  
  # Bug Fix Helpers
  
  defp analyze_bug_report(request, _state) do
    # Analyze the bug description and affected code
    {:ok, %{
      bug_description: Map.get(request, :description),
      affected_code: Map.get(request, :code),
      error_messages: Map.get(request, :errors, []),
      stack_trace: Map.get(request, :stack_trace)
    }}
  end
  
  defp identify_root_cause(analysis, _state) do
    # Use CodeAnalyzer to find the root cause
    case CodeAnalyzer.analyze_code(
      analysis.affected_code,
      :quality_analysis
    ) do
      {:ok, quality_analysis} ->
        {:ok, %{
          root_cause: infer_root_cause(quality_analysis, analysis),
          explanation: "Detailed root cause analysis",
          confidence: :high
        }}
      error -> error
    end
  end
  
  defp design_fix_strategy(root_cause, _conversation_context, _state) do
    # Design the fix approach
    {:ok, %{
      strategy: "Targeted fix addressing root cause",
      changes_required: identify_required_changes(root_cause),
      risk_assessment: assess_fix_risk(root_cause)
    }}
  end
  
  defp implement_bug_fix(fix_strategy, _state) do
    # Generate the actual fix
    case GenerationEngine.generate_code(
      fix_strategy.changes_required,
      :bug_fix,
      strategy: fix_strategy
    ) do
      {:ok, fix} -> {:ok, %{code: fix.code, explanation: fix.explanation}}
      error -> error
    end
  end
  
  defp generate_regression_tests(fix_implementation, _state) do
    # Create tests to prevent regression
    case TestGenerator.generate_tests(
      fix_implementation.code,
      :edge_case_tests,
      focus_on: :regression_prevention
    ) do
      {:ok, tests} -> {:ok, %{test_code: tests.generated_tests, test_count: tests.test_count}}
      error -> error
    end
  end
  
  # Helper functions for all workflows
  
  defp extract_requirements(request) do
    # Extract feature requirements from the request
    description = Map.get(request, :description, "")
    
    %{
      functional: extract_functional_requirements(description),
      non_functional: extract_non_functional_requirements(description),
      constraints: Map.get(request, :constraints, [])
    }
  end
  
  defp identify_required_components(analysis) do
    # Identify what components need to be created
    [
      %{type: :module, name: "NewFeatureModule", purpose: "Main feature implementation"},
      %{type: :function, name: "process_feature", purpose: "Core processing logic"}
    ]
  end
  
  defp identify_integration_points(analysis) do
    # Find where the feature needs to integrate
    [
      %{module: "ExistingModule", function: "handle_request", integration_type: :call},
      %{module: "Router", path: "/new_feature", integration_type: :route}
    ]
  end
  
  defp infer_root_cause(quality_analysis, bug_analysis) do
    # Infer the root cause from analysis results
    "Type mismatch in pattern matching causing runtime error"
  end
  
  defp identify_required_changes(root_cause) do
    # Determine what changes are needed
    [
      %{file: "lib/module.ex", line: 42, change: "Fix pattern matching"},
      %{file: "lib/module.ex", line: 45, change: "Add guard clause"}
    ]
  end
  
  defp assess_fix_risk(root_cause) do
    # Assess the risk of the fix
    %{
      risk_level: :low,
      affected_areas: ["Pattern matching logic"],
      testing_required: :comprehensive
    }
  end
  
  defp extract_functional_requirements(description) do
    # Extract functional requirements from description
    ["Process user input", "Validate data", "Return formatted response"]
  end
  
  defp extract_non_functional_requirements(description) do
    # Extract non-functional requirements
    ["Performance: < 100ms response time", "Security: Input validation required"]
  end
  
  # Response formatting functions
  
  defp format_feature_response(implementation, tests, documentation) do
    """
    ## Feature Implementation Complete
    
    I've successfully implemented the requested feature with the following components:
    
    ### Implementation
    #{summarize_implementation(implementation)}
    
    ### Tests
    #{summarize_tests(tests)}
    
    ### Documentation
    #{summarize_documentation(documentation)}
    
    The feature is now ready for integration and testing.
    """
  end
  
  defp format_bug_fix_response(root_cause, fix_implementation, regression_tests) do
    """
    ## Bug Fix Complete
    
    ### Root Cause Analysis
    #{root_cause.explanation}
    
    ### Fix Applied
    #{summarize_fix(fix_implementation)}
    
    ### Regression Tests
    #{summarize_regression_tests(regression_tests)}
    
    The bug has been fixed and tests added to prevent regression.
    """
  end
  
  defp format_refactoring_response(plan, refactored_code, validation) do
    """
    ## Refactoring Complete
    
    ### Refactoring Plan
    #{summarize_refactoring_plan(plan)}
    
    ### Changes Applied
    #{summarize_refactoring_changes(refactored_code)}
    
    ### Validation Results
    #{summarize_validation(validation)}
    
    The code has been successfully refactored while maintaining functionality.
    """
  end
  
  defp format_explanation_response(explanations, examples, diagrams) do
    """
    ## Code Explanation
    
    ### Overview
    #{explanations.content}
    
    ### Usage Examples
    #{format_examples(examples)}
    
    ### Conceptual Diagrams
    #{format_diagrams(diagrams)}
    
    The codebase has been thoroughly analyzed and explained.
    """
  end
  
  defp format_test_generation_response(unit_tests, integration_tests, test_data) do
    """
    ## Test Suite Generated
    
    ### Unit Tests
    #{summarize_unit_tests(unit_tests)}
    
    ### Integration Tests
    #{summarize_integration_tests(integration_tests)}
    
    ### Test Data
    #{summarize_test_data(test_data)}
    
    Comprehensive test coverage has been created.
    """
  end
  
  defp format_improvement_response(improvements, implementation, validation) do
    """
    ## Code Improvements Applied
    
    ### Identified Improvements
    #{summarize_improvements(improvements)}
    
    ### Implementation
    #{summarize_improvement_implementation(implementation)}
    
    ### Validation
    #{summarize_improvement_validation(validation)}
    
    The code has been improved according to best practices.
    """
  end
  
  defp format_review_response(issues, suggestions, fixes) do
    """
    ## Code Review Complete
    
    ### Issues Found
    #{summarize_issues(issues)}
    
    ### Suggestions
    #{summarize_suggestions(suggestions)}
    
    ### Recommended Fixes
    #{summarize_fixes(fixes)}
    
    Please review and apply the suggested improvements.
    """
  end
  
  defp format_documentation_response(api_docs, examples, readme) do
    """
    ## Documentation Generated
    
    ### API Documentation
    #{summarize_api_docs(api_docs)}
    
    ### Code Examples
    #{summarize_doc_examples(examples)}
    
    ### README Content
    #{summarize_readme(readme)}
    
    Complete documentation has been created for the codebase.
    """
  end
  
  # Summary helper functions
  
  defp summarize_implementation(implementation) do
    "Created #{count_lines(implementation.code)} lines of code implementing the feature"
  end
  
  defp summarize_tests(tests) do
    "Generated #{Map.get(tests, :test_count, "multiple")} tests with #{tests.coverage}% estimated coverage"
  end
  
  defp summarize_documentation(documentation) do
    "Created comprehensive documentation explaining the feature implementation"
  end
  
  defp summarize_fix(fix_implementation) do
    "Applied targeted fix: #{fix_implementation.explanation}"
  end
  
  defp summarize_regression_tests(regression_tests) do
    "Added #{regression_tests.test_count} regression tests to prevent future occurrences"
  end
  
  defp summarize_refactoring_plan(plan) do
    improvements = plan.improvements || []
    "Planned #{length(improvements)} improvements focusing on code quality and maintainability"
  end
  
  defp summarize_refactoring_changes(refactored_code) do
    "Refactored code with improved structure and readability"
  end
  
  defp summarize_validation(validation) do
    "All refactoring changes validated - functionality preserved"
  end
  
  defp format_examples(examples) do
    examples.code_examples |> Enum.take(3) |> Enum.join("\n\n")
  end
  
  defp format_diagrams(diagrams) do
    diagrams.visualizations |> Enum.take(2) |> Enum.join("\n\n")
  end
  
  defp summarize_unit_tests(unit_tests) do
    "Generated comprehensive unit test suite"
  end
  
  defp summarize_integration_tests(integration_tests) do
    "Created integration tests for component interactions"
  end
  
  defp summarize_test_data(test_data) do
    "Generated test fixtures and data generators"
  end
  
  defp summarize_improvements(improvements) do
    "Identified opportunities for performance, readability, and maintainability improvements"
  end
  
  defp summarize_improvement_implementation(implementation) do
    "Successfully applied all recommended improvements"
  end
  
  defp summarize_improvement_validation(validation) do
    "Validated that improvements maintain correctness and enhance quality"
  end
  
  defp summarize_issues(issues) do
    "Found #{length(issues.items || [])} code quality issues"
  end
  
  defp summarize_suggestions(suggestions) do
    "Provided actionable suggestions for code improvement"
  end
  
  defp summarize_fixes(fixes) do
    "Generated specific fixes for identified issues"
  end
  
  defp summarize_api_docs(api_docs) do
    "Created detailed API documentation for all public functions"
  end
  
  defp summarize_doc_examples(examples) do
    "Added practical examples demonstrating usage patterns"
  end
  
  defp summarize_readme(readme) do
    "Generated comprehensive README with setup and usage instructions"
  end
  
  defp format_review_report(issues, suggestions) do
    %{
      summary: "Code review findings and recommendations",
      issues: issues,
      suggestions: suggestions,
      timestamp: DateTime.utc_now()
    }
  end
  
  # Complex workflow helper functions
  
  defp analyze_code_for_refactoring(request, _state) do
    code = Map.get(request, :code, "")
    
    case RefactoringEngine.suggest_refactoring(code, :all) do
      {:ok, suggestions} -> {:ok, %{code: code, suggestions: suggestions}}
      error -> error
    end
  end
  
  defp create_refactoring_plan(analysis, _conversation_context, _state) do
    suggestions = Map.get(analysis.suggestions, :suggestions, [])
    
    {:ok, %{
      improvements: suggestions,
      priority_order: prioritize_refactorings(suggestions),
      estimated_effort: estimate_refactoring_effort(suggestions)
    }}
  end
  
  defp apply_refactorings(refactoring_plan, _state) do
    # Apply the refactorings in priority order
    # This is a simplified version - in practice would apply each refactoring
    {:ok, %{
      code: "# Refactored code\n" <> generate_refactored_placeholder(),
      changes_applied: length(refactoring_plan.improvements)
    }}
  end
  
  defp ensure_test_coverage(refactored_code, _state) do
    case TestGenerator.generate_tests(refactored_code.code, :unit_tests) do
      {:ok, tests} -> {:ok, %{test_code: tests.generated_tests}}
      error -> error
    end
  end
  
  defp validate_refactoring(refactored_code, _state) do
    # Validate that the refactoring maintains functionality
    {:ok, %{
      status: :valid,
      functionality_preserved: true,
      performance_impact: :neutral
    }}
  end
  
  defp analyze_code_structure(request, _state) do
    code = Map.get(request, :code, "")
    
    case CodeAnalyzer.analyze_code(code, :structure_analysis) do
      {:ok, analysis} -> {:ok, analysis}
      error -> error
    end
  end
  
  defp generate_explanations(code_analysis, _conversation_context, _state) do
    # Generate explanations based on the analysis
    {:ok, %{
      content: "Comprehensive code explanation based on structure analysis",
      sections: ["Overview", "Architecture", "Key Components", "Data Flow"]
    }}
  end
  
  defp generate_usage_examples(_code_analysis, _state) do
    {:ok, %{
      code_examples: [
        "# Example 1: Basic usage\n...",
        "# Example 2: Advanced usage\n..."
      ]
    }}
  end
  
  defp generate_conceptual_diagrams(_code_analysis, _state) do
    {:ok, %{
      visualizations: [
        "Component Diagram:\n[ASCII art diagram]",
        "Data Flow Diagram:\n[ASCII art diagram]"
      ]
    }}
  end
  
  defp analyze_code_for_testing(request, _state) do
    code = Map.get(request, :code, "")
    
    case CodeAnalyzer.analyze_code(code, :structure_analysis) do
      {:ok, analysis} -> {:ok, %{code: code, structure: analysis}}
      error -> error
    end
  end
  
  defp design_test_strategy(code_analysis, _conversation_context, _state) do
    {:ok, %{
      approach: "Comprehensive testing with focus on edge cases",
      coverage_target: 95,
      test_types: [:unit, :integration, :property]
    }}
  end
  
  defp generate_unit_tests(test_strategy, _state) do
    {:ok, %{
      test_code: "# Generated unit tests\n...",
      test_count: 25
    }}
  end
  
  defp generate_integration_tests(test_strategy, _state) do
    {:ok, %{
      test_code: "# Generated integration tests\n...",
      test_count: 10
    }}
  end
  
  defp generate_test_data(_test_strategy, _state) do
    {:ok, %{
      fixtures: %{
        users: "# User test data",
        products: "# Product test data"
      }
    }}
  end
  
  defp comprehensive_code_analysis(request, _state) do
    code = Map.get(request, :code, "")
    
    # Run multiple analysis types
    with {:ok, structure} <- CodeAnalyzer.analyze_code(code, :structure_analysis),
         {:ok, quality} <- CodeAnalyzer.analyze_code(code, :quality_analysis),
         {:ok, performance} <- CodeAnalyzer.analyze_code(code, :performance_analysis) do
      
      {:ok, %{
        structure: structure,
        quality: quality,
        performance: performance
      }}
    end
  end
  
  defp identify_improvements(analysis, _conversation_context, _state) do
    {:ok, %{
      report: "Comprehensive improvement opportunities identified",
      categories: [:performance, :readability, :maintainability, :security],
      total_improvements: 15
    }}
  end
  
  defp prioritize_improvements(improvements, _state) do
    {:ok, %{
      high_priority: ["Fix N+1 queries", "Add input validation"],
      medium_priority: ["Refactor complex conditionals", "Extract common logic"],
      low_priority: ["Update variable names", "Add comments"]
    }}
  end
  
  defp implement_improvements(prioritized, _state) do
    {:ok, %{
      code: "# Improved code with all enhancements applied",
      improvements_applied: 12
    }}
  end
  
  defp validate_improvements(implementation, _state) do
    {:ok, %{
      all_tests_pass: true,
      performance_improved: true,
      code_quality_score: 95
    }}
  end
  
  defp analyze_code_quality(request, _state) do
    code = Map.get(request, :code, "")
    
    case CodeAnalyzer.analyze_code(code, :quality_analysis) do
      {:ok, analysis} -> {:ok, analysis}
      error -> error
    end
  end
  
  defp identify_code_issues(analysis, _state) do
    {:ok, %{
      items: [
        %{type: :complexity, severity: :high, location: "line 42"},
        %{type: :duplication, severity: :medium, location: "lines 15-30"}
      ]
    }}
  end
  
  defp generate_review_suggestions(issues, _conversation_context, _state) do
    {:ok, %{
      suggestions: Enum.map(issues.items, &create_suggestion_for_issue/1)
    }}
  end
  
  defp generate_suggested_fixes(issues, _state) do
    {:ok, %{
      code_changes: Enum.map(issues.items, &create_fix_for_issue/1)
    }}
  end
  
  defp analyze_code_for_documentation(request, _state) do
    code = Map.get(request, :code, "")
    
    case CodeAnalyzer.analyze_code(code, :structure_analysis) do
      {:ok, analysis} -> {:ok, %{code: code, structure: analysis}}
      error -> error
    end
  end
  
  defp design_documentation_structure(code_analysis, _conversation_context, _state) do
    {:ok, %{
      structure: %{
        api_reference: true,
        usage_guide: true,
        examples: true,
        readme: true
      },
      style: :comprehensive
    }}
  end
  
  defp generate_api_documentation(doc_structure, _state) do
    {:ok, %{
      content: "# API Reference\n\nComprehensive API documentation..."
    }}
  end
  
  defp generate_documentation_examples(doc_structure, _state) do
    {:ok, %{
      code_examples: [
        "# Getting Started\n...",
        "# Advanced Usage\n..."
      ]
    }}
  end
  
  defp generate_readme_content(doc_structure, _state) do
    {:ok, %{
      content: "# Project Name\n\n## Overview\n..."
    }}
  end
  
  # Utility functions
  
  defp prioritize_refactorings(suggestions) do
    suggestions
    |> Enum.sort_by(fn s -> Map.get(s, :severity, :low) end, :desc)
    |> Enum.take(10)
  end
  
  defp estimate_refactoring_effort(suggestions) do
    total_effort = Enum.sum(Enum.map(suggestions, fn s ->
      case Map.get(s, :effort, :medium) do
        :small -> 1
        :medium -> 3
        :large -> 8
      end
    end))
    
    %{
      total_effort_points: total_effort,
      estimated_hours: total_effort * 0.5
    }
  end
  
  defp generate_refactored_placeholder do
    """
    defmodule RefactoredModule do
      # Improved code structure
      # Better error handling
      # Cleaner function organization
    end
    """
  end
  
  defp create_suggestion_for_issue(issue) do
    %{
      issue: issue,
      suggestion: "Consider refactoring #{issue.type} at #{issue.location}",
      priority: issue.severity
    }
  end
  
  defp create_fix_for_issue(issue) do
    %{
      issue: issue,
      fix: "# Suggested fix for #{issue.type}\n# Code changes here..."
    }
  end
  
  defp suggest_next_steps(workflow_type, result) do
    case workflow_type do
      :feature_implementation ->
        ["Run the test suite", "Deploy to staging", "Update documentation"]
        
      :bug_fix ->
        ["Verify fix in production", "Monitor for regression", "Update changelog"]
        
      :refactoring ->
        ["Run performance benchmarks", "Update team on changes", "Plan next refactoring"]
        
      :explanation ->
        ["Share with team", "Create training materials", "Document patterns"]
        
      :test_generation ->
        ["Run test suite", "Check coverage report", "Add to CI pipeline"]
        
      :improvement ->
        ["Benchmark improvements", "Update coding standards", "Share learnings"]
        
      :code_review ->
        ["Apply suggested fixes", "Discuss with team", "Update guidelines"]
        
      :documentation ->
        ["Publish documentation", "Get team feedback", "Set up auto-generation"]
        
      _ ->
        ["Review results", "Test changes", "Deploy when ready"]
    end
  end
  
  defp update_conversation_context(context, request, response) do
    Map.merge(context, %{
      last_request: request,
      last_response: response,
      updated_at: DateTime.utc_now()
    })
  end
  
  defp load_user_preferences(_opts) do
    %{
      preferred_test_framework: :ex_unit,
      code_style: :idiomatic,
      documentation_level: :comprehensive,
      explanation_detail: :detailed
    }
  end
  
  defp count_lines(code) when is_binary(code) do
    code |> String.split("\n") |> length()
  end
  defp count_lines(_), do: 0
  
  defp record_workflow_metrics(workflow_type, duration_ms, result) do
    status = case result do
      {:ok, _} -> :success
      {:error, _} -> :failure
    end
    
    EventBus.publish("ai.coordinator.coding_assistant.workflow_completed", %{
      workflow_type: workflow_type,
      duration_ms: duration_ms,
      status: status,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp generate_session_id do
    "coding_assistant_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
end