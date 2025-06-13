defmodule Aiex.AI.Distributed.OverrideManager do
  @moduledoc """
  Implements distributed override system for manual response preferences.
  
  This module provides:
  - User-specific override rules
  - Context-based override patterns
  - Administrative override policies
  - Distributed override synchronization
  - Override rule validation and conflict resolution
  - Temporary and permanent override management
  """
  
  use GenServer
  require Logger
  
  alias Aiex.EventBus
  alias Aiex.Telemetry
  
  @pg_scope :aiex_override_manager
  @override_table :response_overrides
  @override_history_table :override_history
  
  @max_override_rules_per_user 50
  @override_sync_interval 300_000  # 5 minutes
  
  defstruct [
    :node_id,
    :override_rules,
    :rule_priorities,
    :conflict_resolver,
    :sync_status,
    :validation_rules,
    :temporary_overrides,
    :administrative_overrides,
    :peer_nodes
  ]
  
  @type override_rule :: %{
    id: String.t(),
    user_id: String.t() | :global,
    context_pattern: map(),
    preference_rule: map(),
    priority: integer(),
    scope: :user | :context | :global | :administrative,
    expires_at: integer() | nil,
    created_by: String.t(),
    created_at: integer(),
    updated_at: integer(),
    active: boolean()
  }
  
  @type override_result :: %{
    applied: boolean(),
    rule_id: String.t() | nil,
    selected_response: any() | nil,
    confidence: float(),
    reasoning: String.t()
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Create a new override rule.
  """
  def create_override_rule(user_id, context_pattern, preference_rule, options \\ []) do
    GenServer.call(__MODULE__, {:create_override_rule, user_id, context_pattern, preference_rule, options})
  end
  
  @doc """
  Apply override rules to response selection.
  """
  def apply_overrides(user_id, context, responses, options \\ []) do
    GenServer.call(__MODULE__, {:apply_overrides, user_id, context, responses, options})
  end
  
  @doc """
  Update an existing override rule.
  """
  def update_override_rule(rule_id, updates) do
    GenServer.call(__MODULE__, {:update_override_rule, rule_id, updates})
  end
  
  @doc """
  Delete an override rule.
  """
  def delete_override_rule(rule_id, deleted_by) do
    GenServer.call(__MODULE__, {:delete_override_rule, rule_id, deleted_by})
  end
  
  @doc """
  Get override rules for a user.
  """
  def get_user_override_rules(user_id) do
    GenServer.call(__MODULE__, {:get_user_override_rules, user_id})
  end
  
  @doc """
  Get all active override rules.
  """
  def get_all_override_rules do
    GenServer.call(__MODULE__, :get_all_override_rules)
  end
  
  @doc """
  Create temporary override (expires automatically).
  """
  def create_temporary_override(user_id, context_pattern, preference_rule, duration_ms) do
    GenServer.call(__MODULE__, {:create_temporary_override, user_id, context_pattern, preference_rule, duration_ms})
  end
  
  @doc """
  Create administrative override (high priority, global scope).
  """
  def create_administrative_override(admin_id, context_pattern, preference_rule, options \\ []) do
    GenServer.call(__MODULE__, {:create_administrative_override, admin_id, context_pattern, preference_rule, options})
  end
  
  @doc """
  Get override statistics and performance metrics.
  """
  def get_override_stats do
    GenServer.call(__MODULE__, :get_override_stats)
  end
  
  @doc """
  Validate override rule before creation.
  """
  def validate_override_rule(context_pattern, preference_rule) do
    GenServer.call(__MODULE__, {:validate_override_rule, context_pattern, preference_rule})
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, Node.self())
    
    # Join pg group for distributed coordination
    :pg.join(@pg_scope, self())
    
    # Initialize Mnesia tables
    initialize_mnesia_tables()
    
    state = %__MODULE__{
      node_id: node_id,
      override_rules: %{},
      rule_priorities: initialize_rule_priorities(),
      conflict_resolver: initialize_conflict_resolver(),
      sync_status: :synchronized,
      validation_rules: initialize_validation_rules(),
      temporary_overrides: %{},
      administrative_overrides: %{},
      peer_nodes: []
    }
    
    # Load existing rules from Mnesia
    loaded_state = load_override_rules_from_mnesia(state)
    
    # Schedule periodic tasks
    schedule_sync()
    schedule_cleanup()
    
    Logger.info("OverrideManager started on node #{node_id}")
    
    {:ok, loaded_state}
  end
  
  @impl true
  def handle_call({:create_override_rule, user_id, context_pattern, preference_rule, options}, _from, state) do
    # Validate the override rule
    case validate_override_rule_internal(context_pattern, preference_rule, state.validation_rules) do
      {:ok, _} ->
        # Check user limits
        if within_user_limits?(user_id, state.override_rules) do
          # Create the rule
          override_rule = create_rule(user_id, context_pattern, preference_rule, options)
          
          # Store in local state and Mnesia
          new_state = add_override_rule(state, override_rule)
          store_override_rule_in_mnesia(override_rule)
          
          # Broadcast to peer nodes
          broadcast_override_rule_update(:create, override_rule)
          
          # Emit event
          emit_override_event(:rule_created, override_rule)
          
          Logger.info("Created override rule #{override_rule.id} for user #{user_id}")
          {:reply, {:ok, override_rule}, new_state}
        else
          {:reply, {:error, :user_rule_limit_exceeded}, state}
        end
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:apply_overrides, user_id, context, responses, options}, _from, state) do
    # Find applicable override rules
    applicable_rules = find_applicable_rules(user_id, context, state)
    
    if Enum.empty?(applicable_rules) do
      # No overrides apply
      result = %{
        applied: false,
        rule_id: nil,
        selected_response: nil,
        confidence: 0.0,
        reasoning: "No applicable override rules found"
      }
      
      {:reply, result, state}
    else
      # Apply the highest priority rule
      highest_priority_rule = select_highest_priority_rule(applicable_rules, state.rule_priorities)
      
      # Apply the override rule
      case apply_override_rule(highest_priority_rule, responses, context, options) do
        {:ok, override_result} ->
          # Record override application
          record_override_application(highest_priority_rule, override_result, user_id, context)
          
          # Update state with usage tracking
          new_state = update_rule_usage(state, highest_priority_rule.id)
          
          {:reply, override_result, new_state}
        
        {:error, reason} ->
          Logger.warn("Failed to apply override rule #{highest_priority_rule.id}: #{reason}")
          
          result = %{
            applied: false,
            rule_id: highest_priority_rule.id,
            selected_response: nil,
            confidence: 0.0,
            reasoning: "Override rule application failed: #{reason}"
          }
          
          {:reply, result, state}
      end
    end
  end
  
  @impl true
  def handle_call({:update_override_rule, rule_id, updates}, _from, state) do
    case Map.get(state.override_rules, rule_id) do
      nil ->
        {:reply, {:error, :rule_not_found}, state}
      
      existing_rule ->
        # Validate updates
        updated_rule = Map.merge(existing_rule, updates)
        updated_rule = %{updated_rule | updated_at: System.system_time(:millisecond)}
        
        case validate_override_rule_internal(updated_rule.context_pattern, updated_rule.preference_rule, state.validation_rules) do
          {:ok, _} ->
            # Update in state and Mnesia
            new_state = %{state | override_rules: Map.put(state.override_rules, rule_id, updated_rule)}
            update_override_rule_in_mnesia(updated_rule)
            
            # Broadcast update
            broadcast_override_rule_update(:update, updated_rule)
            
            # Emit event
            emit_override_event(:rule_updated, updated_rule)
            
            Logger.info("Updated override rule #{rule_id}")
            {:reply, {:ok, updated_rule}, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  @impl true
  def handle_call({:delete_override_rule, rule_id, deleted_by}, _from, state) do
    case Map.get(state.override_rules, rule_id) do
      nil ->
        {:reply, {:error, :rule_not_found}, state}
      
      rule ->
        # Mark as deleted
        deleted_rule = %{rule | active: false, updated_at: System.system_time(:millisecond)}
        
        # Remove from active rules
        new_override_rules = Map.delete(state.override_rules, rule_id)
        new_state = %{state | override_rules: new_override_rules}
        
        # Update in Mnesia (keep for history)
        update_override_rule_in_mnesia(deleted_rule)
        
        # Record deletion in history
        record_override_deletion(rule, deleted_by)
        
        # Broadcast deletion
        broadcast_override_rule_update(:delete, deleted_rule)
        
        # Emit event
        emit_override_event(:rule_deleted, deleted_rule)
        
        Logger.info("Deleted override rule #{rule_id}")
        {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call({:get_user_override_rules, user_id}, _from, state) do
    user_rules = state.override_rules
    |> Map.values()
    |> Enum.filter(&(&1.user_id == user_id and &1.active))
    |> Enum.sort_by(& &1.priority, :desc)
    
    {:reply, user_rules, state}
  end
  
  @impl true
  def handle_call(:get_all_override_rules, _from, state) do
    all_rules = state.override_rules
    |> Map.values()
    |> Enum.filter(& &1.active)
    |> Enum.sort_by(& &1.priority, :desc)
    
    {:reply, all_rules, state}
  end
  
  @impl true
  def handle_call({:create_temporary_override, user_id, context_pattern, preference_rule, duration_ms}, _from, state) do
    expires_at = System.system_time(:millisecond) + duration_ms
    
    options = [
      scope: :temporary,
      expires_at: expires_at,
      priority: 500  # Medium priority for temporary overrides
    ]
    
    case validate_override_rule_internal(context_pattern, preference_rule, state.validation_rules) do
      {:ok, _} ->
        temp_rule = create_rule(user_id, context_pattern, preference_rule, options)
        
        # Add to temporary overrides
        new_temp_overrides = Map.put(state.temporary_overrides, temp_rule.id, temp_rule)
        new_state = %{state | 
          temporary_overrides: new_temp_overrides,
          override_rules: Map.put(state.override_rules, temp_rule.id, temp_rule)
        }
        
        # Schedule expiration
        schedule_temporary_override_expiration(temp_rule.id, duration_ms)
        
        # Broadcast to peers
        broadcast_override_rule_update(:create_temporary, temp_rule)
        
        Logger.info("Created temporary override rule #{temp_rule.id} for #{duration_ms}ms")
        {:reply, {:ok, temp_rule}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:create_administrative_override, admin_id, context_pattern, preference_rule, options}, _from, state) do
    # Administrative overrides have highest priority
    admin_options = [
      scope: :administrative,
      priority: 1000,
      created_by: admin_id
    ] ++ options
    
    case validate_override_rule_internal(context_pattern, preference_rule, state.validation_rules) do
      {:ok, _} ->
        admin_rule = create_rule(:global, context_pattern, preference_rule, admin_options)
        
        # Add to administrative overrides
        new_admin_overrides = Map.put(state.administrative_overrides, admin_rule.id, admin_rule)
        new_state = %{state | 
          administrative_overrides: new_admin_overrides,
          override_rules: Map.put(state.override_rules, admin_rule.id, admin_rule)
        }
        
        # Store in Mnesia
        store_override_rule_in_mnesia(admin_rule)
        
        # Broadcast to peers
        broadcast_override_rule_update(:create_administrative, admin_rule)
        
        # Emit high-priority event
        emit_override_event(:administrative_rule_created, admin_rule)
        
        Logger.warn("Created administrative override rule #{admin_rule.id} by #{admin_id}")
        {:reply, {:ok, admin_rule}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_override_stats, _from, state) do
    stats = %{
      node_id: state.node_id,
      total_rules: map_size(state.override_rules),
      user_rules: count_rules_by_scope(state.override_rules, :user),
      context_rules: count_rules_by_scope(state.override_rules, :context),
      global_rules: count_rules_by_scope(state.override_rules, :global),
      administrative_rules: count_rules_by_scope(state.override_rules, :administrative),
      temporary_rules: map_size(state.temporary_overrides),
      sync_status: state.sync_status,
      peer_nodes: length(state.peer_nodes),
      recent_applications: get_recent_applications(),
      rule_usage_stats: get_rule_usage_stats(state.override_rules),
      timestamp: System.system_time(:millisecond)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:validate_override_rule, context_pattern, preference_rule}, _from, state) do
    result = validate_override_rule_internal(context_pattern, preference_rule, state.validation_rules)
    {:reply, result, state}
  end
  
  @impl true
  def handle_info({:override_rule_update, action, rule}, state) do
    # Received override rule update from peer node
    new_state = case action do
      :create ->
        add_override_rule(state, rule)
      
      :update ->
        %{state | override_rules: Map.put(state.override_rules, rule.id, rule)}
      
      :delete ->
        %{state | override_rules: Map.delete(state.override_rules, rule.id)}
      
      :create_temporary ->
        new_temp_overrides = Map.put(state.temporary_overrides, rule.id, rule)
        %{state | 
          temporary_overrides: new_temp_overrides,
          override_rules: Map.put(state.override_rules, rule.id, rule)
        }
      
      :create_administrative ->
        new_admin_overrides = Map.put(state.administrative_overrides, rule.id, rule)
        %{state | 
          administrative_overrides: new_admin_overrides,
          override_rules: Map.put(state.override_rules, rule.id, rule)
        }
      
      _ ->
        state
    end
    
    Logger.debug("Received override rule update: #{action}")
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:expire_temporary_override, rule_id}, state) do
    # Expire temporary override
    case Map.get(state.temporary_overrides, rule_id) do
      nil ->
        {:noreply, state}
      
      temp_rule ->
        # Remove from active rules
        new_override_rules = Map.delete(state.override_rules, rule_id)
        new_temp_overrides = Map.delete(state.temporary_overrides, rule_id)
        
        new_state = %{state | 
          override_rules: new_override_rules,
          temporary_overrides: new_temp_overrides
        }
        
        # Record expiration
        record_override_expiration(temp_rule)
        
        # Broadcast expiration
        broadcast_override_rule_update(:expire, temp_rule)
        
        Logger.info("Expired temporary override rule #{rule_id}")
        {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_info(:sync_override_rules, state) do
    # Sync override rules with peer nodes
    updated_state = sync_rules_with_peers(state)
    schedule_sync()
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:cleanup_expired_rules, state) do
    # Clean up expired and deleted rules
    updated_state = cleanup_expired_rules(state)
    schedule_cleanup()
    {:noreply, updated_state}
  end
  
  # Private Functions
  
  defp initialize_mnesia_tables do
    # Create Mnesia tables for distributed override storage
    tables = [
      {@override_table, [
        {:attributes, [:id, :user_id, :context_pattern, :preference_rule, :priority, :scope, :expires_at, :created_by, :created_at, :updated_at, :active]},
        {:type, :set},
        {:disc_copies, [Node.self()]}
      ]},
      {@override_history_table, [
        {:attributes, [:id, :rule_id, :action, :user_id, :timestamp, :metadata]},
        {:type, :ordered_set},
        {:disc_copies, [Node.self()]}
      ]}
    ]
    
    Enum.each(tables, fn {table_name, options} ->
      case :mnesia.create_table(table_name, options) do
        {:atomic, :ok} ->
          Logger.debug("Created Mnesia table: #{table_name}")
        
        {:aborted, {:already_exists, ^table_name}} ->
          Logger.debug("Mnesia table already exists: #{table_name}")
        
        error ->
          Logger.error("Failed to create Mnesia table #{table_name}: #{inspect(error)}")
      end
    end)
  end
  
  defp initialize_rule_priorities do
    %{
      administrative: 1000,
      emergency: 900,
      user_critical: 800,
      context_specific: 700,
      user_preference: 600,
      temporary: 500,
      global_default: 400,
      fallback: 100
    }
  end
  
  defp initialize_conflict_resolver do
    %{
      strategy: :highest_priority,
      allow_multiple: false,
      merge_compatible: true
    }
  end
  
  defp initialize_validation_rules do
    %{
      max_context_patterns: 10,
      allowed_preference_types: [:provider, :quality_threshold, :response_format, :exclude_providers],
      required_fields: [:type],
      max_pattern_complexity: 5
    }
  end
  
  defp create_rule(user_id, context_pattern, preference_rule, options) do
    rule_id = generate_rule_id()
    scope = Keyword.get(options, :scope, :user)
    priority = Keyword.get(options, :priority, determine_default_priority(scope))
    expires_at = Keyword.get(options, :expires_at)
    created_by = Keyword.get(options, :created_by, user_id)
    
    %{
      id: rule_id,
      user_id: user_id,
      context_pattern: context_pattern,
      preference_rule: preference_rule,
      priority: priority,
      scope: scope,
      expires_at: expires_at,
      created_by: created_by,
      created_at: System.system_time(:millisecond),
      updated_at: System.system_time(:millisecond),
      active: true
    }
  end
  
  defp determine_default_priority(scope) do
    case scope do
      :administrative -> 1000
      :emergency -> 900
      :user -> 600
      :context -> 700
      :temporary -> 500
      :global -> 400
      _ -> 300
    end
  end
  
  defp add_override_rule(state, rule) do
    new_override_rules = Map.put(state.override_rules, rule.id, rule)
    
    # Also add to specific collections based on scope
    case rule.scope do
      :temporary ->
        new_temp_overrides = Map.put(state.temporary_overrides, rule.id, rule)
        %{state | 
          override_rules: new_override_rules,
          temporary_overrides: new_temp_overrides
        }
      
      :administrative ->
        new_admin_overrides = Map.put(state.administrative_overrides, rule.id, rule)
        %{state | 
          override_rules: new_override_rules,
          administrative_overrides: new_admin_overrides
        }
      
      _ ->
        %{state | override_rules: new_override_rules}
    end
  end
  
  defp validate_override_rule_internal(context_pattern, preference_rule, validation_rules) do
    with :ok <- validate_context_pattern(context_pattern, validation_rules),
         :ok <- validate_preference_rule(preference_rule, validation_rules) do
      {:ok, :valid}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp validate_context_pattern(pattern, validation_rules) do
    max_patterns = validation_rules.max_context_patterns
    
    cond do
      not is_map(pattern) ->
        {:error, :invalid_context_pattern_format}
      
      map_size(pattern) > max_patterns ->
        {:error, :context_pattern_too_complex}
      
      not has_required_pattern_fields?(pattern) ->
        {:error, :missing_required_pattern_fields}
      
      true ->
        :ok
    end
  end
  
  defp validate_preference_rule(rule, validation_rules) do
    allowed_types = validation_rules.allowed_preference_types
    required_fields = validation_rules.required_fields
    
    cond do
      not is_map(rule) ->
        {:error, :invalid_preference_rule_format}
      
      not has_required_fields?(rule, required_fields) ->
        {:error, :missing_required_preference_fields}
      
      not valid_preference_type?(rule, allowed_types) ->
        {:error, :invalid_preference_type}
      
      true ->
        :ok
    end
  end
  
  defp has_required_pattern_fields?(pattern) do
    # Context patterns should have at least a type
    Map.has_key?(pattern, :type) or Map.has_key?(pattern, "type")
  end
  
  defp has_required_fields?(rule, required_fields) do
    Enum.all?(required_fields, fn field ->
      Map.has_key?(rule, field) or Map.has_key?(rule, to_string(field))
    end)
  end
  
  defp valid_preference_type?(rule, allowed_types) do
    rule_type = Map.get(rule, :type) || Map.get(rule, "type")
    rule_type in allowed_types
  end
  
  defp within_user_limits?(user_id, override_rules) do
    user_rule_count = override_rules
    |> Map.values()
    |> Enum.count(&(&1.user_id == user_id and &1.active))
    
    user_rule_count < @max_override_rules_per_user
  end
  
  defp find_applicable_rules(user_id, context, state) do
    state.override_rules
    |> Map.values()
    |> Enum.filter(&rule_applies?(&1, user_id, context))
    |> Enum.filter(&rule_not_expired?/1)
  end
  
  defp rule_applies?(rule, user_id, context) do
    rule.active and
    (rule.user_id == user_id or rule.user_id == :global) and
    context_matches_pattern?(context, rule.context_pattern)
  end
  
  defp rule_not_expired?(rule) do
    case rule.expires_at do
      nil -> true
      expires_at -> System.system_time(:millisecond) < expires_at
    end
  end
  
  defp context_matches_pattern?(context, pattern) do
    # Implement context pattern matching
    Enum.all?(pattern, fn {key, expected_value} ->
      case Map.get(context, key) || Map.get(context, to_string(key)) do
        ^expected_value -> true
        actual_value when is_list(expected_value) -> actual_value in expected_value
        _ -> false
      end
    end)
  end
  
  defp select_highest_priority_rule(rules, rule_priorities) do
    Enum.max_by(rules, fn rule ->
      base_priority = rule.priority
      scope_bonus = Map.get(rule_priorities, rule.scope, 0)
      base_priority + scope_bonus
    end)
  end
  
  defp apply_override_rule(rule, responses, context, _options) do
    case rule.preference_rule.type do
      :provider ->
        apply_provider_preference(rule, responses)
      
      :quality_threshold ->
        apply_quality_threshold(rule, responses)
      
      :response_format ->
        apply_response_format_preference(rule, responses)
      
      :exclude_providers ->
        apply_provider_exclusion(rule, responses)
      
      _ ->
        {:error, :unsupported_preference_type}
    end
  end
  
  defp apply_provider_preference(rule, responses) do
    preferred_provider = rule.preference_rule.provider
    
    case Enum.find(responses, &(Map.get(&1, :provider) == preferred_provider)) do
      nil ->
        {:error, :preferred_provider_not_available}
      
      response ->
        {:ok, %{
          applied: true,
          rule_id: rule.id,
          selected_response: response,
          confidence: 1.0,
          reasoning: "Selected #{preferred_provider} as per user override rule"
        }}
    end
  end
  
  defp apply_quality_threshold(rule, responses) do
    threshold = rule.preference_rule.minimum_quality
    
    qualified_responses = Enum.filter(responses, fn response ->
      quality = Map.get(response, :quality_score, 0.0)
      quality >= threshold
    end)
    
    case qualified_responses do
      [] ->
        {:error, :no_responses_meet_quality_threshold}
      
      [response | _] ->
        {:ok, %{
          applied: true,
          rule_id: rule.id,
          selected_response: response,
          confidence: 0.9,
          reasoning: "Selected response meeting quality threshold #{threshold}"
        }}
    end
  end
  
  defp apply_response_format_preference(rule, responses) do
    preferred_format = rule.preference_rule.format
    
    case find_response_with_format(responses, preferred_format) do
      nil ->
        {:error, :preferred_format_not_available}
      
      response ->
        {:ok, %{
          applied: true,
          rule_id: rule.id,
          selected_response: response,
          confidence: 0.8,
          reasoning: "Selected response with preferred format: #{preferred_format}"
        }}
    end
  end
  
  defp apply_provider_exclusion(rule, responses) do
    excluded_providers = rule.preference_rule.excluded_providers
    
    allowed_responses = Enum.reject(responses, fn response ->
      provider = Map.get(response, :provider)
      provider in excluded_providers
    end)
    
    case allowed_responses do
      [] ->
        {:error, :all_providers_excluded}
      
      [response | _] ->
        {:ok, %{
          applied: true,
          rule_id: rule.id,
          selected_response: response,
          confidence: 0.7,
          reasoning: "Selected response from non-excluded provider"
        }}
    end
  end
  
  defp find_response_with_format(responses, format) do
    # Simple format detection based on content
    Enum.find(responses, fn response ->
      content = extract_content(response)
      
      case format do
        :code -> String.contains?(content, "```")
        :markdown -> String.contains?(content, "#") or String.contains?(content, "*")
        :plain_text -> not String.contains?(content, "```") and not String.contains?(content, "#")
        _ -> false
      end
    end)
  end
  
  defp extract_content(response) do
    case response do
      %{content: content} when is_binary(content) -> content
      %{"content" => content} when is_binary(content) -> content
      binary when is_binary(binary) -> binary
      _ -> inspect(response)
    end
  end
  
  defp store_override_rule_in_mnesia(rule) do
    transaction = fn ->
      :mnesia.write({@override_table,
        rule.id,
        rule.user_id,
        rule.context_pattern,
        rule.preference_rule,
        rule.priority,
        rule.scope,
        rule.expires_at,
        rule.created_by,
        rule.created_at,
        rule.updated_at,
        rule.active
      })
    end
    
    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        :ok
      
      {:aborted, reason} ->
        Logger.error("Failed to store override rule in Mnesia: #{inspect(reason)}")
        :error
    end
  end
  
  defp update_override_rule_in_mnesia(rule) do
    store_override_rule_in_mnesia(rule)
  end
  
  defp load_override_rules_from_mnesia(state) do
    transaction = fn ->
      :mnesia.match_object({@override_table, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, true})
    end
    
    case :mnesia.transaction(transaction) do
      {:atomic, records} ->
        loaded_rules = Enum.map(records, &mnesia_record_to_rule/1)
        
        override_rules = Enum.reduce(loaded_rules, %{}, fn rule, acc ->
          Map.put(acc, rule.id, rule)
        end)
        
        %{state | override_rules: override_rules}
      
      {:aborted, reason} ->
        Logger.error("Failed to load override rules from Mnesia: #{inspect(reason)}")
        state
    end
  end
  
  defp mnesia_record_to_rule({@override_table, id, user_id, context_pattern, preference_rule, priority, scope, expires_at, created_by, created_at, updated_at, active}) do
    %{
      id: id,
      user_id: user_id,
      context_pattern: context_pattern,
      preference_rule: preference_rule,
      priority: priority,
      scope: scope,
      expires_at: expires_at,
      created_by: created_by,
      created_at: created_at,
      updated_at: updated_at,
      active: active
    }
  end
  
  defp broadcast_override_rule_update(action, rule) do
    pg_members = :pg.get_members(@pg_scope)
    
    Enum.each(pg_members, fn member ->
      if member != self() do
        send(member, {:override_rule_update, action, rule})
      end
    end)
  end
  
  defp record_override_application(rule, result, user_id, context) do
    history_entry = %{
      id: generate_history_id(),
      rule_id: rule.id,
      action: :applied,
      user_id: user_id,
      timestamp: System.system_time(:millisecond),
      metadata: %{
        context: context,
        result: result,
        confidence: result.confidence
      }
    }
    
    store_history_entry(history_entry)
  end
  
  defp record_override_deletion(rule, deleted_by) do
    history_entry = %{
      id: generate_history_id(),
      rule_id: rule.id,
      action: :deleted,
      user_id: deleted_by,
      timestamp: System.system_time(:millisecond),
      metadata: %{
        deleted_rule: rule
      }
    }
    
    store_history_entry(history_entry)
  end
  
  defp record_override_expiration(rule) do
    history_entry = %{
      id: generate_history_id(),
      rule_id: rule.id,
      action: :expired,
      user_id: :system,
      timestamp: System.system_time(:millisecond),
      metadata: %{
        expired_rule: rule
      }
    }
    
    store_history_entry(history_entry)
  end
  
  defp store_history_entry(entry) do
    transaction = fn ->
      :mnesia.write({@override_history_table,
        entry.id,
        entry.rule_id,
        entry.action,
        entry.user_id,
        entry.timestamp,
        entry.metadata
      })
    end
    
    case :mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        :ok
      
      {:aborted, reason} ->
        Logger.error("Failed to store history entry in Mnesia: #{inspect(reason)}")
        :error
    end
  end
  
  defp update_rule_usage(state, rule_id) do
    # Track rule usage for analytics
    # In this implementation, we'll just log it
    Logger.debug("Override rule #{rule_id} was applied")
    state
  end
  
  defp emit_override_event(event_type, rule) do
    EventBus.emit("override_#{event_type}", %{
      rule_id: rule.id,
      user_id: rule.user_id,
      scope: rule.scope,
      priority: rule.priority,
      node_id: Node.self()
    })
  end
  
  defp count_rules_by_scope(rules, scope) do
    rules
    |> Map.values()
    |> Enum.count(&(&1.scope == scope and &1.active))
  end
  
  defp get_recent_applications do
    # Would query from history table in real implementation
    []
  end
  
  defp get_rule_usage_stats(rules) do
    # Calculate usage statistics
    total_rules = map_size(rules)
    active_rules = Enum.count(Map.values(rules), & &1.active)
    
    %{
      total_rules: total_rules,
      active_rules: active_rules,
      inactive_rules: total_rules - active_rules
    }
  end
  
  defp schedule_temporary_override_expiration(rule_id, duration_ms) do
    Process.send_after(self(), {:expire_temporary_override, rule_id}, duration_ms)
  end
  
  defp sync_rules_with_peers(state) do
    # Sync override rules with peer nodes
    Logger.debug("Syncing override rules with peer nodes")
    state
  end
  
  defp cleanup_expired_rules(state) do
    # Clean up expired rules
    current_time = System.system_time(:millisecond)
    
    active_rules = Enum.filter(state.override_rules, fn {_id, rule} ->
      case rule.expires_at do
        nil -> true
        expires_at -> expires_at > current_time
      end
    end) |> Enum.into(%{})
    
    %{state | override_rules: active_rules}
  end
  
  defp generate_rule_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp generate_history_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp schedule_sync do
    Process.send_after(self(), :sync_override_rules, @override_sync_interval)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired_rules, @override_sync_interval * 2)
  end
end