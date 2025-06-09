defmodule Aiex.LLM.Templates.SimpleTemplateTest do
  use ExUnit.Case, async: true
  
  alias Aiex.LLM.Templates.{TemplateEngine, TemplateRegistry}
  
  test "basic template functionality" do
    # Start a minimal template system without loading defaults
    children = [
      {TemplateEngine, []},
      {TemplateRegistry, [skip_defaults: true]}
    ]
    
    {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
    
    # Simple template with minimal structure  
    template_data = %{
      name: "simple test",
      description: "Simple test template",
      version: "1.0.0",
      category: :test,
      intent: :test,
      content: "Hello {{name}}!",
      variables: [
        %{name: "name", type: :string, required: true}
      ],
      conditions: [],
      metadata: %{}
    }
    
    # Register template
    assert {:ok, _} = TemplateRegistry.register_template(:simple_test, template_data, [])
    
    # Get template
    assert {:ok, template} = TemplateRegistry.get_template(:simple_test)
    assert template.content == "Hello {{name}}!"
    
    # Render template
    variables = %{name: "World"}
    assert {:ok, rendered} = TemplateEngine.render_template(:simple_test, variables, %{})
    assert rendered =~ "Hello World"
  end
end