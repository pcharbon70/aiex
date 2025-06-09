defmodule Aiex.LLM.Templates.TemplateSystemTest do
  use ExUnit.Case, async: true
  
  alias Aiex.LLM.Templates.{TemplateEngine, TemplateRegistry, Template}
  
  describe "template system integration" do
    test "can start template system" do
      # Start the template supervisor
      {:ok, _pid} = Aiex.LLM.Templates.Supervisor.start_link([])
      
      # Verify template engine is running
      assert Process.whereis(TemplateEngine) != nil
      
      # Verify template registry is running  
      assert Process.whereis(TemplateRegistry) != nil
    end
    
    test "can register and retrieve templates" do
      # Start the template supervisor
      {:ok, _pid} = Aiex.LLM.Templates.Supervisor.start_link([])
      
      # Create a simple template
      template_data = %{
        name: "test template",
        description: "Test template",
        version: "1.0.0",
        category: :operation,
        intent: :test,
        content: "Hello {{name}}!",
        variables: [
          %{name: "name", type: :string, required: true}
        ],
        conditions: [],
        metadata: %{}
      }
      
      # Register the template
      assert {:ok, _state} = TemplateRegistry.register_template(:test_template, template_data, [])
      
      # Retrieve the template
      assert {:ok, template} = TemplateRegistry.get_template(:test_template)
      assert template.content == "Hello {{name}}!"
    end
    
    test "can render templates with variables" do
      # Start the template supervisor
      {:ok, _pid} = Aiex.LLM.Templates.Supervisor.start_link([])
      
      # Create and register a template
      template_data = %{
        name: "greeting template",
        description: "Test template",
        version: "1.0.0", 
        category: :operation,
        intent: :test,
        content: "Hello {{name}}, you are {{age}} years old!",
        variables: [
          %{name: "name", type: :string, required: true},
          %{name: "age", type: :integer, required: true}
        ],
        conditions: [],
        metadata: %{}
      }
      
      TemplateRegistry.register_template(:greeting_template, template_data, [])
      
      # Render the template
      variables = %{name: "Alice", age: 30}
      assert {:ok, rendered} = TemplateEngine.render_template(:greeting_template, variables, %{})
      
      assert rendered =~ "Hello Alice"
      assert rendered =~ "30 years old"
    end
    
    test "can get default operation templates" do
      # Start the template supervisor
      {:ok, _pid} = Aiex.LLM.Templates.Supervisor.start_link([])
      
      # Check that default templates are loaded
      assert {:ok, analyze_template} = TemplateRegistry.get_template(:operation_analyze)
      assert analyze_template.content =~ "Analyze the following Elixir code"
      
      assert {:ok, explain_template} = TemplateRegistry.get_template(:operation_explain)
      assert explain_template.content =~ "Explain the following Elixir code"
    end
  end
  
  describe "template content generation" do
    test "generates appropriate analyze template" do
      # Start the template supervisor
      {:ok, _pid} = Aiex.LLM.Templates.Supervisor.start_link([])
      
      # Get analyze template and render it
      {:ok, template} = TemplateRegistry.get_template(:operation_analyze)
      
      variables = %{
        code_content: "defmodule Test do\n  def hello, do: :world\nend",
        analysis_focus: "performance"
      }
      
      {:ok, rendered} = TemplateEngine.render_template(:operation_analyze, variables, %{})
      
      assert rendered =~ "defmodule Test"
      assert rendered =~ "performance"
      assert rendered =~ "Code structure and organization"
    end
    
    test "generates appropriate implementation template" do
      # Start the template supervisor
      {:ok, _pid} = Aiex.LLM.Templates.Supervisor.start_link([])
      
      # Get workflow implementation template
      {:ok, template} = TemplateRegistry.get_template(:workflow_implement_feature)
      
      variables = %{
        feature_description: "Add user authentication",
        project_context: %{
          project_name: "MyApp",
          framework: "Phoenix"
        }
      }
      
      {:ok, rendered} = TemplateEngine.render_template(:workflow_implement_feature, variables, %{})
      
      assert rendered =~ "Add user authentication"
      assert rendered =~ "MyApp"
      assert rendered =~ "Phoenix"
      assert rendered =~ "OTP design patterns"
    end
  end
end