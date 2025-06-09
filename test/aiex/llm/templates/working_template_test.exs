defmodule Aiex.LLM.Templates.WorkingTemplateTest do
  use ExUnit.Case, async: false
  
  alias Aiex.LLM.Templates.{TemplateEngine, TemplateRegistry}
  
  describe "template system functionality" do
    test "can retrieve default workflow templates" do
      # The template system should be started by the main application
      # Check that default templates are available
      assert {:ok, implement_template} = TemplateRegistry.get_template(:workflow_implement_feature)
      assert implement_template.content =~ "Implement the feature"
      assert implement_template.intent == :implement_feature
      
      assert {:ok, fix_template} = TemplateRegistry.get_template(:workflow_fix_bug)
      assert fix_template.content =~ "Bug Report"
      assert fix_template.intent == :fix_bug
    end
    
    test "can register custom templates" do
      # Register a simple custom template
      template_data = %{
        name: "custom test",
        description: "Custom test template", 
        version: "1.0.0",
        category: :test,
        intent: :custom_test,
        content: "This is a custom template with variable: {{test_var}}",
        variables: [
          %{name: "test_var", type: :string, required: true}
        ],
        conditions: [],
        metadata: %{}
      }
      
      assert {:ok, _} = TemplateRegistry.register_template(:custom_test_template, template_data, [])
      
      # Verify we can retrieve it
      assert {:ok, template} = TemplateRegistry.get_template(:custom_test_template)
      assert template.content =~ "custom template"
      assert template.intent == :custom_test
    end
    
    test "can render simple templates" do
      # Register a simple template for rendering
      template_data = %{
        name: "greeting",
        description: "Simple greeting template",
        version: "1.0.0",
        category: :test,
        intent: :greeting,
        content: "Hello {{name}}, welcome to {{platform}}!",
        variables: [
          %{name: "name", type: :string, required: true},
          %{name: "platform", type: :string, required: true}
        ],
        conditions: [],
        metadata: %{}
      }
      
      TemplateRegistry.register_template(:greeting_template, template_data, [])
      
      # Render the template
      variables = %{name: "Alice", platform: "Aiex"}
      assert {:ok, rendered} = TemplateEngine.render_template(:greeting_template, variables, %{})
      
      assert rendered =~ "Hello Alice"
      assert rendered =~ "welcome to Aiex"
    end
  end
end