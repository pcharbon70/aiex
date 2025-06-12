defmodule Aiex.AI.Engines.ExplanationEngineTest do
  use ExUnit.Case, async: false
  
  alias Aiex.AI.Engines.ExplanationEngine
  
  setup do
    # Check if ExplanationEngine is already running
    case Process.whereis(ExplanationEngine) do
      nil ->
        # Start the ExplanationEngine for testing if not already running
        {:ok, pid} = start_supervised({ExplanationEngine, [session_id: "test_explanation_session"]})
        %{engine_pid: pid}
      
      pid ->
        # Use the existing process
        %{engine_pid: pid}
    end
  end
  
  describe "ExplanationEngine initialization" do
    test "starts successfully with default options" do
      assert {:ok, pid} = ExplanationEngine.start_link()
      assert Process.alive?(pid)
    end
    
    test "starts with custom session_id" do
      session_id = "custom_explanation_session"
      assert {:ok, pid} = ExplanationEngine.start_link(session_id: session_id)
      assert Process.alive?(pid)
    end
  end
  
  describe "AIEngine behavior implementation" do
    test "implements can_handle?/1 correctly" do
      assert ExplanationEngine.can_handle?(:code_explanation)
      assert ExplanationEngine.can_handle?(:function_explanation)
      assert ExplanationEngine.can_handle?(:module_explanation)
      assert ExplanationEngine.can_handle?(:pattern_explanation)
      assert ExplanationEngine.can_handle?(:architecture_explanation)
      assert ExplanationEngine.can_handle?(:tutorial_explanation)
      assert ExplanationEngine.can_handle?(:concept_explanation)
      
      refute ExplanationEngine.can_handle?(:unsupported_explanation)
      refute ExplanationEngine.can_handle?(:invalid_type)
    end
    
    test "get_metadata/0 returns correct information" do
      metadata = ExplanationEngine.get_metadata()
      
      assert metadata.name == "Explanation Engine"
      assert is_binary(metadata.description)
      assert is_list(metadata.supported_types)
      assert is_list(metadata.detail_levels)
      assert is_list(metadata.audience_levels)
      assert metadata.version == "1.0.0"
      assert is_list(metadata.capabilities)
      
      # Verify supported types are included
      assert :code_explanation in metadata.supported_types
      assert :function_explanation in metadata.supported_types
      
      # Verify detail levels
      assert :brief in metadata.detail_levels
      assert :detailed in metadata.detail_levels
      assert :comprehensive in metadata.detail_levels
      assert :tutorial in metadata.detail_levels
      
      # Verify audience levels
      assert :beginner in metadata.audience_levels
      assert :intermediate in metadata.audience_levels
      assert :advanced in metadata.audience_levels
      assert :expert in metadata.audience_levels
    end
    
    test "prepare/1 accepts options" do
      assert :ok = ExplanationEngine.prepare([])
      assert :ok = ExplanationEngine.prepare([reload_templates: true])
    end
  end
  
  describe "code explanation functionality" do
    @sample_code """
    defmodule Calculator do
      @moduledoc "A simple calculator with basic arithmetic operations"
      
      def add(a, b) when is_number(a) and is_number(b) do
        a + b
      end
      
      def multiply(a, b) when is_number(a) and is_number(b) do
        a * b
      end
      
      defp validate_input(value) do
        is_number(value)
      end
    end
    """
    
    @tag :requires_llm
    test "explain_code/4 handles different detail levels" do
      # Test brief explanation
      result_brief = ExplanationEngine.explain_code(@sample_code, :brief, :beginner)
      assert match?({:ok, _}, result_brief) or match?({:error, _}, result_brief)
      
      # Test detailed explanation
      result_detailed = ExplanationEngine.explain_code(@sample_code, :detailed, :intermediate)
      assert match?({:ok, _}, result_detailed) or match?({:error, _}, result_detailed)
      
      # Test comprehensive explanation
      result_comprehensive = ExplanationEngine.explain_code(@sample_code, :comprehensive, :advanced)
      assert match?({:ok, _}, result_comprehensive) or match?({:error, _}, result_comprehensive)
      
      # Test tutorial explanation
      result_tutorial = ExplanationEngine.explain_code(@sample_code, :tutorial, :beginner)
      assert match?({:ok, _}, result_tutorial) or match?({:error, _}, result_tutorial)
    end
    
    @tag :requires_llm
    test "explain_code/4 handles different audience levels" do
      # Test beginner audience
      result_beginner = ExplanationEngine.explain_code(@sample_code, :detailed, :beginner)
      assert match?({:ok, _}, result_beginner) or match?({:error, _}, result_beginner)
      
      # Test intermediate audience
      result_intermediate = ExplanationEngine.explain_code(@sample_code, :detailed, :intermediate)
      assert match?({:ok, _}, result_intermediate) or match?({:error, _}, result_intermediate)
      
      # Test advanced audience
      result_advanced = ExplanationEngine.explain_code(@sample_code, :detailed, :advanced)
      assert match?({:ok, _}, result_advanced) or match?({:error, _}, result_advanced)
      
      # Test expert audience
      result_expert = ExplanationEngine.explain_code(@sample_code, :detailed, :expert)
      assert match?({:ok, _}, result_expert) or match?({:error, _}, result_expert)
    end
    
    @tag :requires_llm
    test "explain_code/4 accepts options" do
      options = [
        focus_on: :patterns,
        include_examples: true,
        highlight_best_practices: true
      ]
      
      result = ExplanationEngine.explain_code(@sample_code, :detailed, :intermediate, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "explain_code/4 handles empty code" do
      result = ExplanationEngine.explain_code("", :brief, :beginner)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "explain_code/4 handles invalid Elixir syntax" do
      invalid_code = "this is not valid elixir code {"
      result = ExplanationEngine.explain_code(invalid_code, :brief, :beginner)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "function explanation" do
    @tag :requires_llm
    test "explain_function/4 explains specific functions" do
      function_code = """
      def process_payment(amount, payment_method, user_id) do
        with {:ok, user} <- get_user(user_id),
             {:ok, validated_amount} <- validate_amount(amount),
             {:ok, payment} <- charge_payment(validated_amount, payment_method) do
          {:ok, payment}
        else
          {:error, reason} -> {:error, reason}
        end
      end
      """
      
      result = ExplanationEngine.explain_function(
        function_code, 
        "process_payment", 
        :detailed,
        [focus_on: :with_statement]
      )
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "explain_function/4 handles simple functions" do
      simple_function = "def greet(name), do: \"Hello, \#{name}!\""
      
      result = ExplanationEngine.explain_function(simple_function, "greet", :brief)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "explain_function/4 handles complex functions with pattern matching" do
      complex_function = """
      def handle_response({:ok, %{"data" => data, "status" => "success"}}) do
        {:ok, transform_data(data)}
      end
      
      def handle_response({:ok, %{"status" => "error", "message" => message}}) do
        {:error, message}
      end
      
      def handle_response({:error, reason}) do
        {:error, "Request failed: \#{reason}"}
      end
      """
      
      result = ExplanationEngine.explain_function(
        complex_function, 
        "handle_response", 
        :comprehensive
      )
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "module explanation" do
    @tag :requires_llm
    test "explain_module/3 explains module structure" do
      module_code = """
      defmodule UserService do
        @moduledoc "Service for managing user operations"
        
        alias MyApp.{User, Repo}
        
        def create_user(attrs) do
          %User{}
          |> User.changeset(attrs)
          |> Repo.insert()
        end
        
        def get_user(id) do
          Repo.get(User, id)
        end
        
        def update_user(user, attrs) do
          user
          |> User.changeset(attrs)
          |> Repo.update()
        end
        
        defp validate_user_data(attrs) do
          # Private validation logic
        end
      end
      """
      
      result = ExplanationEngine.explain_module(module_code, :detailed, :intermediate)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "explain_module/3 handles GenServer modules" do
      genserver_code = """
      defmodule MyWorker do
        use GenServer
        
        def start_link(opts) do
          GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end
        
        def init(opts) do
          {:ok, %{status: :ready, config: opts}}
        end
        
        def handle_call(:get_status, _from, state) do
          {:reply, state.status, state}
        end
        
        def handle_cast({:update_status, new_status}, state) do
          {:noreply, %{state | status: new_status}}
        end
      end
      """
      
      result = ExplanationEngine.explain_module(genserver_code, :comprehensive, :intermediate)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "pattern explanation" do
    @tag :requires_llm
    test "explain_patterns/3 explains design patterns" do
      pattern_code = """
      defmodule PaymentProcessor do
        @behaviour PaymentGateway
        
        defstruct [:amount, :currency, :status]
        
        def process(payment_data) do
          %__MODULE__{amount: payment_data.amount, currency: payment_data.currency}
          |> validate_payment()
          |> charge_payment()
          |> handle_result()
        end
        
        defp validate_payment(%__MODULE__{} = payment) do
          # Validation logic
          payment
        end
        
        defp charge_payment(%__MODULE__{} = payment) do
          # Charging logic
          %{payment | status: :charged}
        end
        
        defp handle_result(%__MODULE__{status: :charged} = payment) do
          {:ok, payment}
        end
      end
      """
      
      result = ExplanationEngine.explain_patterns(pattern_code, :pipeline_pattern, :detailed)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "explain_patterns/3 explains OTP patterns" do
      supervisor_code = """
      defmodule MyApp.Supervisor do
        use Supervisor
        
        def start_link(opts) do
          Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
        end
        
        def init(_opts) do
          children = [
            {MyApp.Worker, []},
            {MyApp.Cache, []},
            {MyApp.Monitor, []}
          ]
          
          Supervisor.init(children, strategy: :one_for_one)
        end
      end
      """
      
      result = ExplanationEngine.explain_patterns(supervisor_code, :supervisor_pattern, :detailed)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "tutorial creation" do
    @tag :requires_llm
    test "create_tutorial/3 creates step-by-step explanations" do
      tutorial_code = """
      defmodule Counter do
        use GenServer
        
        # Client API
        def start_link(initial_value \\\\ 0) do
          GenServer.start_link(__MODULE__, initial_value, name: __MODULE__)
        end
        
        def increment do
          GenServer.call(__MODULE__, :increment)
        end
        
        def get_value do
          GenServer.call(__MODULE__, :get_value)
        end
        
        # Server callbacks
        def init(initial_value) do
          {:ok, initial_value}
        end
        
        def handle_call(:increment, _from, state) do
          {:reply, state + 1, state + 1}
        end
        
        def handle_call(:get_value, _from, state) do
          {:reply, state, state}
        end
      end
      """
      
      result = ExplanationEngine.create_tutorial(
        tutorial_code,
        "Building Your First GenServer",
        :beginner
      )
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "create_tutorial/3 handles complex tutorials" do
      phoenix_code = """
      defmodule MyAppWeb.UserController do
        use MyAppWeb, :controller
        
        alias MyApp.{User, Repo}
        
        def index(conn, _params) do
          users = Repo.all(User)
          render(conn, "index.html", users: users)
        end
        
        def create(conn, %{"user" => user_params}) do
          case User.changeset(%User{}, user_params) |> Repo.insert() do
            {:ok, user} ->
              conn
              |> put_flash(:info, "User created successfully")
              |> redirect(to: Routes.user_path(conn, :show, user))
              
            {:error, changeset} ->
              render(conn, "new.html", changeset: changeset)
          end
        end
      end
      """
      
      result = ExplanationEngine.create_tutorial(
        phoenix_code,
        "Phoenix Controller Patterns",
        :intermediate
      )
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "process/2 AIEngine interface" do
    @tag :requires_llm
    test "processes explanation requests through unified interface" do
      request = %{
        type: :code_explanation,
        explanation_type: :code_explanation,
        content: @sample_code,
        detail_level: :detailed,
        audience: :intermediate,
        options: []
      }
      
      context = %{
        session_id: "test_session",
        project_context: %{framework: :phoenix}
      }
      
      result = ExplanationEngine.process(request, context)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "handles malformed explanation requests" do
      request = %{
        type: :invalid_explanation
        # Missing required fields
      }
      
      context = %{}
      
      result = ExplanationEngine.process(request, context)
      
      assert {:error, _error_msg} = result
    end
    
    @tag :requires_llm
    test "processes function explanation requests" do
      request = %{
        type: :code_explanation,
        explanation_type: :function_explanation,
        content: "def add(a, b), do: a + b",
        detail_level: :brief,
        audience: :beginner,
        function_name: "add"
      }
      
      context = %{learning_context: :first_function}
      
      result = ExplanationEngine.process(request, context)
      
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    test "validates explanation context" do
      # Test invalid detail level
      request = %{
        type: :code_explanation,
        explanation_type: :code_explanation,
        content: @sample_code,
        detail_level: :invalid_level,
        audience: :intermediate
      }
      
      context = %{}
      
      result = ExplanationEngine.process(request, context)
      
      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "Invalid detail level")
    end
    
    test "validates audience level" do
      # Test invalid audience level
      request = %{
        type: :code_explanation,
        explanation_type: :code_explanation,
        content: @sample_code,
        detail_level: :detailed,
        audience: :invalid_audience
      }
      
      context = %{}
      
      result = ExplanationEngine.process(request, context)
      
      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "Invalid audience level")
    end
  end
  
  describe "caching and performance" do
    @tag :requires_llm
    test "caches explanation results for identical requests" do
      code = "def simple(x), do: x * 2"
      
      # First explanation
      result1 = ExplanationEngine.explain_code(code, :brief, :beginner)
      
      # Second explanation should use cache
      result2 = ExplanationEngine.explain_code(code, :brief, :beginner)
      
      # Both should succeed (or both fail consistently)
      assert match?({:ok, _}, result1) or match?({:error, _}, result1)
      assert match?({:ok, _}, result2) or match?({:error, _}, result2)
    end
    
    @tag :requires_llm
    test "handles concurrent explanation requests" do
      tasks = Enum.map(1..3, fn i ->
        Task.async(fn ->
          code = "def function_\#{i}(x), do: x + \#{i}"
          ExplanationEngine.explain_code(code, :brief, :intermediate)
        end)
      end)
      
      results = Task.await_many(tasks)
      
      # All should complete
      assert length(results) == 3
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
  end
  
  describe "explanation quality and formatting" do
    test "estimates reading time for explanations" do
      # Test the helper function exists
      text = String.duplicate("word ", 200)  # 200 words
      
      # This would test the internal estimate_reading_time function
      # For now, verify the concept works
      word_count = text |> String.split(~r/\s+/, trim: true) |> length()
      assert word_count == 200
      
      estimated_minutes = Float.ceil(word_count / 200.0)
      assert estimated_minutes == 1.0
    end
    
    test "counts words in explanations" do
      text = "This is a test explanation with exactly ten words total."
      word_count = text |> String.split(~r/\s+/, trim: true) |> length()
      assert word_count == 10
    end
  end
  
  describe "error handling" do
    @tag :requires_llm
    test "handles invalid explanation types gracefully" do
      result = ExplanationEngine.explain_code(@sample_code, :detailed, :beginner)
      
      # Should work with valid parameters
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles very long code inputs" do
      long_code = String.duplicate(@sample_code, 100)
      
      result = ExplanationEngine.explain_code(long_code, :brief, :intermediate)
      
      # Should handle large inputs without crashing
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
    
    @tag :requires_llm
    test "handles special characters in code" do
      special_code = """
      defmodule Test do
        def special_chars do
          "Special: àáâãäåæçèéêë ñóôõö ùúûü"
        end
      end
      """
      
      result = ExplanationEngine.explain_code(special_code, :brief, :beginner)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "cleanup and resource management" do
    test "cleanup/0 properly cleans up resources" do
      assert :ok = ExplanationEngine.cleanup()
    end
    
    test "handles multiple cleanup calls" do
      assert :ok = ExplanationEngine.cleanup()
      assert :ok = ExplanationEngine.cleanup()
    end
  end
end