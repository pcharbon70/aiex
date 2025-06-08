defmodule Aiex.LLM.Templates.Supervisor do
  @moduledoc """
  Supervisor for the prompt template system.
  
  Manages the template engine and registry processes, ensuring
  fault tolerance and proper startup order.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    children = [
      # Template registry starts first
      {Aiex.LLM.Templates.TemplateRegistry, opts},
      
      # Template engine depends on registry
      {Aiex.LLM.Templates.TemplateEngine, opts}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end