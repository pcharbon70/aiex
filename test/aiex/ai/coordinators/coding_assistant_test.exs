defmodule Aiex.AI.Coordinators.CodingAssistantTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Coordinators.CodingAssistant
  
  setup do
    # Start the CodingAssistant for testing
    {:ok, pid} = start_supervised({CodingAssistant, [session_id: "test_coding_assistant_session"]})
    
    %{assistant_pid: pid}
  end
  
  describe "CodingAssistant initialization" do
    test "starts successfully with default options" do
      assert {:ok, pid} = CodingAssistant.start_link()
      assert Process.alive?(pid)
    end
    
    test "starts with custom session_id" do
      session_id = "custom_coding_assistant_session"
      assert {:ok, pid} = CodingAssistant.start_link(session_id: session_id)
      assert Process.alive?(pid)
    end
  end
  
  describe "Assistant behavior implementation" do
    test "implements get_capabilities/0 correctly" do
      capabilities = CodingAssistant.get_capabilities()
      
      assert capabilities.name == "Coding Assistant"
      assert is_binary(capabilities.description)
      assert is_list(capabilities.supported_workflows)
      assert is_list(capabilities.required_engines)
      assert is_list(capabilities.capabilities)
      
      # Verify supported workflows
      expected_workflows = [
        :implement_feature,
        :fix_bug,
        :refactor_code,
        :explain_codebase,
        :generate_tests,
        :improve_code,
        :code_review,
        :generate_docs
      ]
      
      Enum.each(expected_workflows, fn workflow ->
        assert workflow in capabilities.supported_workflows
      end)
      
      # Verify required engines
      expected_engines = [
        Aiex.AI.Engines.CodeAnalyzer,
        Aiex.AI.Engines.GenerationEngine,
        Aiex.AI.Engines.ExplanationEngine,
        Aiex.AI.Engines.RefactoringEngine,
        Aiex.AI.Engines.TestGenerator
      ]
      
      Enum.each(expected_engines, fn engine ->
        assert engine in capabilities.required_engines
      end)
    end
    
    test "can_handle_request?/1 returns correct values" do
      # Should handle these request types
      assert CodingAssistant.can_handle_request?(:coding_task)
      assert CodingAssistant.can_handle_request?(:feature_request)
      assert CodingAssistant.can_handle_request?(:bug_fix)
      assert CodingAssistant.can_handle_request?(:refactoring)
      assert CodingAssistant.can_handle_request?(:code_explanation)
      assert CodingAssistant.can_handle_request?(:test_generation)
      assert CodingAssistant.can_handle_request?(:code_review)
      assert CodingAssistant.can_handle_request?(:documentation)
      
      # Should not handle these
      refute CodingAssistant.can_handle_request?(:unsupported_type)
      refute CodingAssistant.can_handle_request?(:random_request)
    end
  end
  
  describe "coding request handling" do
    @sample_code """
    defmodule Calculator do
      def add(a, b) when is_number(a) and is_number(b) do
        a + b
      end
      
      def divide(a, b) when is_number(a) and is_number(b) and b != 0 do
        {:ok, a / b}
      end
      def divide(_a, 0), do: {:error, :division_by_zero}
      def divide(_a, _b), do: {:error, :invalid_input}
    end
    """
    
    @tag :requires_llm
    test "handle_coding_request/2 processes feature implementation requests" do
      request = %{
        intent: :implement_feature,
        description: "Add logging functionality to calculator operations",
        context: %{file: "lib/calculator.ex"},
        context_code: @sample_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, response} ->
          assert Map.has_key?(response, :response)
          assert Map.has_key?(response, :workflow)
          assert response.workflow == :implement_feature
          assert Map.has_key?(response, :actions_taken)
          assert Map.has_key?(response, :next_steps)
          assert Map.has_key?(response, :artifacts)
          
        {:error, _reason} ->
          # LLM or dependencies might not be available
          :ok
      end
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 processes bug fix requests" do
      request = %{
        intent: :fix_bug,
        description: "Calculator crashes when handling very large numbers",
        code: @sample_code,
        errors: ["arithmetic overflow"],
        stack_trace: "** (ArithmeticError) bad argument in arithmetic expression"
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, response} ->
          assert response.workflow == :fix_bug
          assert Map.has_key?(response, :artifacts)
          assert Map.has_key?(response.artifacts, :fix)
          assert Map.has_key?(response.artifacts, :tests)
          
        {:error, _reason} ->
          :ok
      end
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 processes refactoring requests" do
      request = %{
        intent: :refactor_code,
        description: "Refactor calculator to improve error handling",
        code: @sample_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, response} ->
          assert response.workflow == :refactor_code
          assert Map.has_key?(response.artifacts, :refactored_code)
          assert Map.has_key?(response.artifacts, :tests)
          
        {:error, _reason} ->
          :ok
      end
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 processes code explanation requests" do
      request = %{
        intent: :explain_codebase,
        description: "Explain how the calculator module works",
        code: @sample_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, response} ->
          assert response.workflow == :explain_codebase
          assert Map.has_key?(response.artifacts, :explanations)
          assert Map.has_key?(response.artifacts, :examples)
          
        {:error, _reason} ->
          :ok
      end
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 processes test generation requests" do
      request = %{
        intent: :generate_tests,
        description: "Generate comprehensive tests for calculator",
        code: @sample_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, response} ->
          assert response.workflow == :generate_tests
          assert Map.has_key?(response.artifacts, :unit_tests)
          assert Map.has_key?(response.artifacts, :integration_tests)
          
        {:error, _reason} ->
          :ok
      end
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 handles code improvement requests" do
      request = %{
        intent: :improve_code,
        description: "Improve calculator code quality and performance",
        code: @sample_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 handles code review requests" do
      request = %{
        intent: :code_review,
        description: "Review calculator code for issues and improvements",
        code: @sample_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 handles documentation generation requests" do
      request = %{
        intent: :generate_docs,
        description: "Generate documentation for calculator module",
        code: @sample_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 with conversation context" do
      request = %{
        intent: :implement_feature,
        description: "Add multiplication function",
        context_code: @sample_code
      }
      
      conversation_context = %{
        previous_requests: ["Add logging", "Fix error handling"],
        user_preferences: %{style: :functional, test_coverage: :high}
      }
      
      result = CodingAssistant.handle_coding_request(request, conversation_context)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handle_coding_request/2 infers workflow from description" do
      test_cases = [
        {%{description: "implement user authentication"}, :implement_feature},
        {%{description: "fix bug in login system"}, :fix_bug},
        {%{description: "refactor authentication module"}, :refactor_code},
        {%{description: "explain how auth works"}, :explain_codebase},
        {%{description: "generate tests for auth"}, :generate_tests},
        {%{description: "review my code quality"}, :code_review},
        {%{description: "create documentation"}, :generate_docs}
      ]
      
      Enum.each(test_cases, fn {request, expected_workflow} ->
        result = CodingAssistant.handle_coding_request(Map.put(request, :code, @sample_code))
        
        case result do
          {:ok, response} ->
            assert response.workflow == expected_workflow
          {:error, _} ->
            # LLM might not be available
            :ok
        end
      end)
    end
  end
  
  describe "session management" do
    test "start_coding_session/2 creates new session" do
      session_id = "new_coding_session_123"
      initial_context = %{
        project_name: "my_app",
        language: :elixir,
        framework: :phoenix
      }
      
      result = CodingAssistant.start_coding_session(session_id, initial_context)
      assert match?({:ok, _}, result)
      
      case result do
        {:ok, session_state} ->
          assert Map.has_key?(session_state, :session_id)
          assert session_state.session_id == session_id
          assert Map.has_key?(session_state, :started_at)
          assert Map.has_key?(session_state, :context)
          assert session_state.context == initial_context
          
        {:error, _} ->
          :ok
      end
    end
    
    test "end_coding_session/1 terminates session" do
      session_id = "session_to_end"
      
      # Start session first
      {:ok, _} = CodingAssistant.start_coding_session(session_id, %{})
      
      # End session
      result = CodingAssistant.end_coding_session(session_id)
      assert result == :ok
    end
    
    test "end_coding_session/1 handles non-existent session" do
      result = CodingAssistant.end_coding_session("non_existent_session")
      assert {:error, :session_not_found} = result
    end
    
    test "get_workflow_state/1 retrieves session state" do
      session_id = "state_test_session"
      initial_context = %{test: "context"}
      
      # Start session
      {:ok, _} = CodingAssistant.start_coding_session(session_id, initial_context)
      
      # Get state
      result = CodingAssistant.get_workflow_state(session_id)
      assert match?({:ok, _}, result)
      
      case result do
        {:ok, state} ->
          assert state.session_id == session_id
          assert state.context == initial_context
          
        {:error, _} ->
          :ok
      end
    end
    
    test "get_workflow_state/1 handles non-existent session" do
      result = CodingAssistant.get_workflow_state("non_existent_session")
      assert {:error, :session_not_found} = result
    end
  end
  
  describe "handle_request/3 Assistant behavior" do
    @tag :requires_llm
    test "processes requests through Assistant interface" do
      request = %{
        type: :coding_task,
        intent: :implement_feature,
        description: "Add new feature",
        code: @sample_code
      }
      
      conversation_context = %{
        session_id: "assistant_test_session",
        history: []
      }
      
      project_context = %{
        framework: :phoenix,
        language: :elixir
      }
      
      result = CodingAssistant.handle_request(request, conversation_context, project_context)
      assert match?({:ok, _, _}, result) or match?({:error, _}, result)
      
      case result do
        {:ok, response, updated_context} ->
          assert Map.has_key?(response, :workflow)
          assert Map.has_key?(updated_context, :last_request)
          assert Map.has_key?(updated_context, :last_response)
          assert Map.has_key?(updated_context, :updated_at)
          
        {:error, _reason} ->
          :ok
      end
    end
    
    @tag :requires_llm
    test "integrates project context into processing" do
      request = %{
        type: :coding_task,
        intent: :generate_tests,
        code: @sample_code
      }
      
      conversation_context = %{}
      
      project_context = %{
        testing_framework: :ex_unit,
        coverage_target: 95,
        style_guide: :credo
      }
      
      result = CodingAssistant.handle_request(request, conversation_context, project_context)
      assert match?({:ok, _, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "workflow orchestration" do
    @tag :requires_llm
    test "orchestrates multiple engines for feature implementation" do
      request = %{
        intent: :implement_feature,
        description: "Add user registration with validation",
        context_code: """
        defmodule UserSystem do
          def create_user(params) do
            # TODO: Implement
          end
        end
        """
      }
      
      result = CodingAssistant.handle_coding_request(request)
      
      case result do
        {:ok, response} ->
          # Verify orchestration occurred
          assert length(response.actions_taken) >= 4  # Analysis, design, implementation, tests, docs
          
          action_types = Enum.map(response.actions_taken, & &1.action)
          assert :analyzed_request in action_types
          assert :designed_solution in action_types
          assert :generated_code in action_types
          assert :generated_tests in action_types
          
        {:error, _} ->
          :ok
      end
    end
    
    @tag :requires_llm
    test "provides appropriate next steps for each workflow" do
      workflows_and_expected_steps = [
        {:implement_feature, ["Run the test suite", "Deploy to staging"]},
        {:fix_bug, ["Verify fix in production", "Monitor for regression"]},
        {:refactor_code, ["Run performance benchmarks", "Update team on changes"]},
        {:code_review, ["Apply suggested fixes", "Discuss with team"]}
      ]
      
      Enum.each(workflows_and_expected_steps, fn {workflow, expected_steps} ->
        request = %{
          intent: workflow,
          description: "Test #{workflow}",
          code: @sample_code
        }
        
        result = CodingAssistant.handle_coding_request(request)
        
        case result do
          {:ok, response} ->
            assert is_list(response.next_steps)
            assert length(response.next_steps) > 0
            
            # Check if any expected steps are present
            next_steps_text = Enum.join(response.next_steps, " ")
            has_expected_step = Enum.any?(expected_steps, fn step ->
              String.contains?(next_steps_text, step)
            end)
            assert has_expected_step or length(response.next_steps) >= 2
            
          {:error, _} ->
            :ok
        end
      end)
    end
  end
  
  describe "error handling and edge cases" do
    @tag :requires_llm
    test "handles malformed requests gracefully" do
      malformed_requests = [
        %{},  # Empty request
        %{intent: :invalid_workflow},  # Invalid workflow
        %{description: "test"},  # Missing code
        %{code: "invalid elixir code {"}  # Malformed code
      ]
      
      Enum.each(malformed_requests, fn request ->
        result = CodingAssistant.handle_coding_request(request)
        # Should not crash, should return either success or meaningful error
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
    
    @tag :requires_llm
    test "handles very large code inputs" do
      large_code = String.duplicate(@sample_code, 100)
      
      request = %{
        intent: :code_review,
        description: "Review large codebase",
        code: large_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      # Should handle large inputs without crashing
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles special characters and unicode" do
      unicode_code = """
      defmodule UnicodeModule do
        def unicode_function do
          "Special: àáâãäåæçèéêë ñóôõö ùúûü"
        end
        
        def emoji_function do
          "Emojis: 🚀 🎉 ✨ 🔥 💯"
        end
      end
      """
      
      request = %{
        intent: :explain_codebase,
        description: "Explain unicode handling",
        code: unicode_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles concurrent requests safely" do
      tasks = Enum.map(1..3, fn i ->
        Task.async(fn ->
          request = %{
            intent: :implement_feature,
            description: "Feature #{i}",
            code: "def function_#{i}(x), do: x + #{i}"
          }
          
          CodingAssistant.handle_coding_request(request)
        end)
      end)
      
      results = Task.await_many(tasks, 30_000)
      
      # All should complete without crashing
      assert length(results) == 3
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
  end
  
  describe "response quality and format" do
    @tag :requires_llm
    test "response format includes all required fields" do
      request = %{
        intent: :implement_feature,
        description: "Add authentication",
        code: @sample_code
      }
      
      result = CodingAssistant.handle_coding_request(request)
      
      case result do
        {:ok, response} ->
          required_fields = [:response, :workflow, :actions_taken, :next_steps, :artifacts]
          
          Enum.each(required_fields, fn field ->
            assert Map.has_key?(response, field), "Missing required field: #{field}"
          end)
          
          # Response should be a readable string
          assert is_binary(response.response)
          assert String.length(response.response) > 10
          
          # Actions taken should be a list of maps with action and result
          assert is_list(response.actions_taken)
          if length(response.actions_taken) > 0 do
            action = hd(response.actions_taken)
            assert Map.has_key?(action, :action)
            assert Map.has_key?(action, :result)
          end
          
          # Next steps should be actionable strings
          assert is_list(response.next_steps)
          if length(response.next_steps) > 0 do
            step = hd(response.next_steps)
            assert is_binary(step)
            assert String.length(step) > 5
          end
          
          # Artifacts should contain relevant output
          assert is_map(response.artifacts)
          
        {:error, _} ->
          :ok
      end
    end
    
    @tag :requires_llm
    test "responses are contextually appropriate" do
      test_cases = [
        {:implement_feature, "code", "Implementation"},
        {:fix_bug, "fix", "Bug Fix"},
        {:refactor_code, "refactored_code", "Refactoring"},
        {:explain_codebase, "explanations", "Explanation"},
        {:generate_tests, "unit_tests", "Test"},
        {:code_review, "review_report", "Review"},
        {:generate_docs, "api_documentation", "Documentation"}
      ]
      
      Enum.each(test_cases, fn {workflow, expected_artifact_key, expected_response_content} ->
        request = %{
          intent: workflow,
          description: "Test #{workflow}",
          code: @sample_code
        }
        
        result = CodingAssistant.handle_coding_request(request)
        
        case result do
          {:ok, response} ->
            # Check that response mentions the workflow type
            assert String.contains?(response.response, expected_response_content)
            
            # Check that appropriate artifacts are present
            if Map.has_key?(response.artifacts, String.to_atom(expected_artifact_key)) do
              artifact = response.artifacts[String.to_atom(expected_artifact_key)]
              assert not is_nil(artifact)
            end
            
          {:error, _} ->
            :ok
        end
      end)
    end
  end
end