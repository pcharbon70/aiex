defmodule Aiex.LLM.Templates.TemplateEngine do
  @moduledoc """
  Main engine for the prompt template system.
  
  Coordinates template loading, compilation, context injection,
  and rendering to provide a unified interface for AI prompt generation.
  """
  
  use GenServer
  require Logger
  
  alias Aiex.LLM.Templates.{
    Template,
    TemplateRegistry,
    TemplateCompiler,
    TemplateValidator,
    ContextInjector
  }
  
  @engine_name __MODULE__
  
  defstruct [
    :registry,
    :context_injector,
    :config,
    :performance_metrics,
    :cache
  ]
  
  @type render_options :: %{
    context_injection: boolean(),
    validation: boolean(),
    caching: boolean(),
    performance_tracking: boolean()
  }
  
  @type render_result :: %{
    rendered_content: String.t() | list(),
    template_metadata: map(),
    context_metadata: map(),
    performance_metrics: map()
  }
  
  @default_options %{
    context_injection: true,
    validation: true,
    caching: true,
    performance_tracking: true
  }
  
  ## Public API
  
  @doc """
  Start the template engine.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @engine_name)
  end
  
  @doc """
  Render a template by ID with the given request data and options.
  """
  @spec render_template(atom(), map(), render_options()) :: {:ok, render_result()} | {:error, term()}
  def render_template(template_id, request_data, options \\ @default_options) do
    GenServer.call(@engine_name, {:render_template, template_id, request_data, options})
  end
  
  @doc """
  Render a template struct directly.
  """
  @spec render_template_struct(Template.t(), map(), render_options()) :: {:ok, render_result()} | {:error, term()}
  def render_template_struct(%Template{} = template, request_data, options \\ @default_options) do
    GenServer.call(@engine_name, {:render_template_struct, template, request_data, options})
  end
  
  @doc """
  Select and render the best template for a given intent and context.
  """
  @spec render_for_intent(atom(), map(), render_options()) :: {:ok, render_result()} | {:error, term()}
  def render_for_intent(intent, request_data, options \\ @default_options) do
    GenServer.call(@engine_name, {:render_for_intent, intent, request_data, options})
  end
  
  @doc """
  Register a new template in the system.
  """
  @spec register_template(Template.t() | map()) :: {:ok, atom()} | {:error, term()}
  def register_template(template_data) do
    GenServer.call(@engine_name, {:register_template, template_data})
  end
  
  @doc """
  Get available templates by criteria.
  """
  @spec list_templates(map()) :: {:ok, [Template.t()]} | {:error, term()}
  def list_templates(criteria \\ %{}) do
    GenServer.call(@engine_name, {:list_templates, criteria})
  end
  
  @doc """
  Validate a template before use.
  """
  @spec validate_template(Template.t() | map()) :: {:ok, map()} | {:error, term()}
  def validate_template(template_data) do
    GenServer.call(@engine_name, {:validate_template, template_data})
  end
  
  @doc """
  Get template engine performance metrics.
  """
  @spec get_metrics() :: {:ok, map()}
  def get_metrics do
    GenServer.call(@engine_name, :get_metrics)
  end
  
  @doc """
  Clear template cache.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    GenServer.call(@engine_name, :clear_cache)
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    # Start template registry
    {:ok, registry_pid} = TemplateRegistry.start_link(opts)
    
    # Initialize context injector
    context_injector = ContextInjector.init(
      Keyword.get(opts, :context_config, [])
    )
    
    config = %{
      cache_ttl_ms: Keyword.get(opts, :cache_ttl_ms, 300_000),  # 5 minutes
      max_cache_size: Keyword.get(opts, :max_cache_size, 1000),
      enable_performance_tracking: Keyword.get(opts, :enable_performance_tracking, true),
      validation_level: Keyword.get(opts, :validation_level, :strict)
    }
    
    state = %__MODULE__{
      registry: registry_pid,
      context_injector: context_injector,
      config: config,
      performance_metrics: %{
        renders_total: 0,
        renders_success: 0,
        renders_error: 0,
        avg_render_time_ms: 0.0,
        cache_hits: 0,
        cache_misses: 0
      },
      cache: %{}
    }
    
    Logger.info("Template engine started successfully")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:render_template, template_id, request_data, options}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    result = case get_template_from_registry(state, template_id) do
      {:ok, template} ->
        render_template_impl(state, template, request_data, options)
      {:error, reason} ->
        {:error, reason}
    end
    
    end_time = System.monotonic_time(:millisecond)
    
    # Update metrics
    new_state = update_performance_metrics(state, result, end_time - start_time)
    
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:render_template_struct, template, request_data, options}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    result = render_template_impl(state, template, request_data, options)
    
    end_time = System.monotonic_time(:millisecond)
    
    # Update metrics
    new_state = update_performance_metrics(state, result, end_time - start_time)
    
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:render_for_intent, intent, request_data, options}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    result = case TemplateRegistry.select_template(intent, request_data) do
      {:ok, template_id} ->
        case get_template_from_registry(state, template_id) do
          {:ok, template} ->
            render_template_impl(state, template, request_data, options)
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
    
    end_time = System.monotonic_time(:millisecond)
    
    # Update metrics
    new_state = update_performance_metrics(state, result, end_time - start_time)
    
    {:reply, result, new_state}
  end
  
  @impl true
  def handle_call({:register_template, template_data}, _from, state) do
    result = case normalize_template_data(template_data) do
      {:ok, template} ->
        case TemplateRegistry.register_template(template.id, template) do
          :ok -> {:ok, template.id}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:list_templates, criteria}, _from, state) do
    result = TemplateRegistry.find_templates(criteria)
    {:reply, result, state}
  end
  
  @impl true
  def handle_call({:validate_template, template_data}, _from, state) do
    result = case normalize_template_data(template_data) do
      {:ok, template} ->
        TemplateValidator.quality_check(template)
      {:error, reason} ->
        {:error, reason}
    end
    
    {:reply, result, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, {:ok, state.performance_metrics}, state}
  end
  
  @impl true
  def handle_call(:clear_cache, _from, state) do
    new_state = %{state | cache: %{}}
    {:reply, :ok, new_state}
  end
  
  ## Private Implementation
  
  defp render_template_impl(state, template, request_data, options) do
    with {:ok, validated_template} <- maybe_validate_template(template, options),
         {:ok, cache_key} <- generate_cache_key(validated_template, request_data, options),
         {:ok, rendered_content, context_metadata} <- render_with_caching(state, validated_template, request_data, options, cache_key) do
      
      result = %{
        rendered_content: rendered_content,
        template_metadata: extract_template_metadata(validated_template),
        context_metadata: context_metadata,
        performance_metrics: %{
          cached: is_cached_result(state, cache_key),
          template_complexity: estimate_template_complexity(validated_template)
        }
      }
      
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp maybe_validate_template(template, options) do
    if options.validation do
      case TemplateValidator.validate(template) do
        {:ok, validated_template} -> {:ok, validated_template}
        {:error, errors} -> {:error, {:validation_failed, errors}}
      end
    else
      {:ok, template}
    end
  end
  
  defp generate_cache_key(template, request_data, options) do
    if options.caching do
      # Generate a cache key based on template ID, request data hash, and options
      request_hash = :crypto.hash(:md5, :erlang.term_to_binary(request_data))
      options_hash = :crypto.hash(:md5, :erlang.term_to_binary(options))
      
      cache_key = {template.id, request_hash, options_hash}
      {:ok, cache_key}
    else
      {:ok, nil}
    end
  end
  
  defp render_with_caching(state, template, request_data, options, cache_key) do
    case cache_key && Map.get(state.cache, cache_key) do
      nil ->
        # Cache miss or caching disabled
        case render_template_core(state, template, request_data, options) do
          {:ok, rendered_content, context_metadata} = result ->
            # Cache the result if caching is enabled
            if cache_key do
              # In practice, you'd implement proper cache with TTL
              # For now, just proceed without caching
            end
            result
          {:error, reason} ->
            {:error, reason}
        end
      
      cached_result ->
        # Cache hit
        cached_result
    end
  end
  
  defp render_template_core(state, template, request_data, options) do
    with {:ok, compiled_template} <- TemplateCompiler.compile(template),
         {:ok, {rendered_content, context_metadata}} <- maybe_inject_context(state, compiled_template, request_data, options) do
      {:ok, rendered_content, context_metadata}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp maybe_inject_context(state, compiled_template, request_data, options) do
    if options.context_injection do
      case ContextInjector.inject_context(state.context_injector, compiled_template, request_data) do
        {:ok, {rendered_content, context_result}} ->
          {:ok, {rendered_content, context_result}}
        {:error, reason} ->
          {:error, {:context_injection_failed, reason}}
      end
    else
      # Render without context injection
      case TemplateCompiler.render(compiled_template, request_data) do
        {:ok, rendered_content} ->
          {:ok, {rendered_content, %{}}}
        {:error, reason} ->
          {:error, {:render_failed, reason}}
      end
    end
  end
  
  defp get_template_from_registry(state, template_id) do
    TemplateRegistry.get_template(template_id)
  end
  
  defp normalize_template_data(%Template{} = template) do
    {:ok, template}
  end
  
  defp normalize_template_data(template_map) when is_map(template_map) do
    Template.from_map(template_map)
  end
  
  defp normalize_template_data(_invalid) do
    {:error, :invalid_template_data}
  end
  
  defp update_performance_metrics(state, result, duration_ms) do
    metrics = state.performance_metrics
    
    new_metrics = %{
      renders_total: metrics.renders_total + 1,
      renders_success: metrics.renders_success + (if match?({:ok, _}, result), do: 1, else: 0),
      renders_error: metrics.renders_error + (if match?({:error, _}, result), do: 1, else: 0),
      avg_render_time_ms: calculate_new_average(metrics.avg_render_time_ms, metrics.renders_total, duration_ms)
    }
    
    %{state | performance_metrics: new_metrics}
  end
  
  defp calculate_new_average(current_avg, count, new_value) do
    if count == 0 do
      new_value
    else
      ((current_avg * count) + new_value) / (count + 1)
    end
  end
  
  defp extract_template_metadata(template) do
    %{
      id: template.id,
      name: template.name,
      version: template.version,
      category: template.category,
      variable_count: length(template.variables),
      conditional_count: length(template.conditionals)
    }
  end
  
  defp estimate_template_complexity(template) do
    # Simple complexity estimation
    base_complexity = 1
    variable_complexity = length(template.variables) * 2
    conditional_complexity = length(template.conditionals) * 3
    
    content_complexity = case template.content do
      content when is_binary(content) -> div(String.length(content), 100)
      content when is_list(content) -> length(content) * 2
      _ -> 0
    end
    
    base_complexity + variable_complexity + conditional_complexity + content_complexity
  end
  
  defp is_cached_result(state, cache_key) do
    cache_key && Map.has_key?(state.cache, cache_key)
  end
end