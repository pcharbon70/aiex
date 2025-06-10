defmodule Aiex.AI.Coordinators.ConversationManager do
  @moduledoc """
  Multi-turn conversation manager that maintains conversation context,
  manages conversation flow, and coordinates with other AI assistants.
  
  The ConversationManager handles:
  - Multi-turn conversation continuity
  - Context preservation across messages
  - Conversation state management
  - Integration with specialized assistants
  - Conversation memory and summarization
  - Intent recognition and routing
  """
  
  use GenServer
  require Logger
  
  @behaviour Aiex.AI.Behaviours.Assistant
  
  alias Aiex.AI.Coordinators.CodingAssistant
  alias Aiex.Context.Manager, as: ContextManager
  alias Aiex.Events.EventBus
  alias Aiex.LLM.ModelCoordinator
  
  # Conversation types supported
  @conversation_types [
    :coding_conversation,     # Technical coding discussions
    :general_conversation,    # General assistant conversations
    :project_conversation,    # Project-specific discussions
    :debugging_conversation,  # Debugging and troubleshooting
    :learning_conversation,   # Educational conversations
    :planning_conversation    # Project planning and architecture
  ]
  
  # Maximum conversation history length before summarization
  @max_history_length 50
  @context_window_size 20
  @summarization_threshold 30
  
  defstruct [
    :session_id,
    :conversations,          # Map of conversation_id -> conversation_state
    :active_assistants,      # Map of assistant type -> assistant instance
    :conversation_memory,    # Long-term conversation memory
    :intent_classifier,      # Intent classification cache
    :conversation_summaries  # Conversation summaries for context
  ]
  
  ## Public API
  
  @doc """
  Starts the ConversationManager coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Starts a new conversation with the specified type and context.
  
  ## Examples
  
      iex> ConversationManager.start_conversation("conv_123", :coding_conversation, %{
      ...>   project: "my_app",
      ...>   language: "elixir"
      ...> })
      {:ok, %{conversation_id: "conv_123", ...}}
  """
  def start_conversation(conversation_id, conversation_type, initial_context \\ %{}) do
    GenServer.call(__MODULE__, {:start_conversation, conversation_id, conversation_type, initial_context})
  end
  
  @doc """
  Continues an existing conversation with a new message.
  """
  def continue_conversation(conversation_id, message, user_context \\ %{}) do
    GenServer.call(__MODULE__, {:continue_conversation, conversation_id, message, user_context}, 60_000)
  end
  
  @doc """
  Ends a conversation and cleans up resources.
  """
  def end_conversation(conversation_id) do
    GenServer.call(__MODULE__, {:end_conversation, conversation_id})
  end
  
  @doc """
  Gets the current state of a conversation.
  """
  def get_conversation_state(conversation_id) do
    GenServer.call(__MODULE__, {:get_conversation_state, conversation_id})
  end
  
  @doc """
  Lists all active conversations.
  """
  def list_conversations do
    GenServer.call(__MODULE__, :list_conversations)
  end
  
  @doc """
  Clears conversation history while preserving essential context.
  """
  def clear_conversation_history(conversation_id, preserve_last_n \\ 5) do
    GenServer.call(__MODULE__, {:clear_history, conversation_id, preserve_last_n})
  end
  
  @doc """
  Gets conversation summary for context preservation.
  """
  def get_conversation_summary(conversation_id) do
    GenServer.call(__MODULE__, {:get_summary, conversation_id})
  end
  
  @doc """
  Searches conversation history for relevant context.
  """
  def search_conversation_history(conversation_id, query, limit \\ 10) do
    GenServer.call(__MODULE__, {:search_history, conversation_id, query, limit})
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
    request_type in [:conversation, :multi_turn_chat, :context_management, 
                    :conversation_continuation, :intent_routing]
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
      name: "Conversation Manager",
      description: "Multi-turn conversation coordinator with context management",
      supported_workflows: @conversation_types,
      required_engines: [
        CodingAssistant
      ],
      capabilities: [
        "Multi-turn conversation management",
        "Context preservation across messages",
        "Intent recognition and routing",
        "Conversation summarization",
        "Assistant coordination",
        "Memory management",
        "Conversation search and retrieval"
      ]
    }
  end
  
  ## GenServer Implementation
  
  @impl GenServer
  def init(opts) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())
    
    state = %__MODULE__{
      session_id: session_id,
      conversations: %{},
      active_assistants: initialize_assistants(),
      conversation_memory: %{},
      intent_classifier: %{},
      conversation_summaries: %{}
    }
    
    Logger.info("ConversationManager started with session_id: #{session_id}")
    
    EventBus.publish("ai.coordinator.conversation_manager.started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:start_conversation, conversation_id, conversation_type, initial_context}, _from, state) do
    case create_new_conversation(conversation_id, conversation_type, initial_context, state) do
      {:ok, conversation_state, updated_state} ->
        {:reply, {:ok, conversation_state}, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:continue_conversation, conversation_id, message, user_context}, _from, state) do
    case process_conversation_message(conversation_id, message, user_context, state) do
      {:ok, response, updated_state} ->
        {:reply, {:ok, response}, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:end_conversation, conversation_id}, _from, state) do
    case finalize_conversation(conversation_id, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_conversation_state, conversation_id}, _from, state) do
    case Map.get(state.conversations, conversation_id) do
      nil -> {:reply, {:error, :conversation_not_found}, state}
      conversation -> {:reply, {:ok, conversation}, state}
    end
  end
  
  @impl GenServer
  def handle_call(:list_conversations, _from, state) do
    conversations = state.conversations
    |> Enum.map(fn {id, conv} ->
      %{
        conversation_id: id,
        type: conv.conversation_type,
        started_at: conv.started_at,
        last_activity: conv.last_activity,
        message_count: length(conv.history)
      }
    end)
    
    {:reply, {:ok, conversations}, state}
  end
  
  @impl GenServer
  def handle_call({:clear_history, conversation_id, preserve_last_n}, _from, state) do
    case clear_conversation_history_impl(conversation_id, preserve_last_n, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:get_summary, conversation_id}, _from, state) do
    case generate_conversation_summary(conversation_id, state) do
      {:ok, summary} ->
        {:reply, {:ok, summary}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:search_history, conversation_id, query, limit}, _from, state) do
    case search_conversation_history_impl(conversation_id, query, limit, state) do
      {:ok, results} ->
        {:reply, {:ok, results}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:handle_request_behavior, request, conversation_context, project_context}, _from, state) do
    case handle_conversation_request(request, conversation_context, project_context, state) do
      {:ok, response, updated_context, updated_state} ->
        {:reply, {:ok, response, updated_context}, updated_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:start_session, session_id, initial_context}, _from, state) do
    new_session_state = %{
      session_id: session_id,
      started_at: DateTime.utc_now(),
      context: initial_context,
      conversations: %{}
    }
    
    EventBus.publish("ai.coordinator.conversation_manager.session_started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, {:ok, new_session_state}, state}
  end
  
  @impl GenServer
  def handle_call({:end_session, session_id}, _from, state) do
    # Clean up session-specific resources
    EventBus.publish("ai.coordinator.conversation_manager.session_ended", %{
      session_id: session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:reply, :ok, state}
  end
  
  ## Private Implementation
  
  defp create_new_conversation(conversation_id, conversation_type, initial_context, state) do
    if Map.has_key?(state.conversations, conversation_id) do
      {:error, :conversation_already_exists}
    else
      conversation_state = %{
        conversation_id: conversation_id,
        conversation_type: conversation_type,
        started_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now(),
        context: initial_context,
        history: [],
        current_intent: nil,
        active_assistant: determine_initial_assistant(conversation_type),
        metadata: %{
          turn_count: 0,
          total_tokens: 0,
          quality_score: 100
        }
      }
      
      updated_conversations = Map.put(state.conversations, conversation_id, conversation_state)
      updated_state = %{state | conversations: updated_conversations}
      
      EventBus.publish("ai.coordinator.conversation_manager.conversation_started", %{
        conversation_id: conversation_id,
        conversation_type: conversation_type,
        timestamp: DateTime.utc_now()
      })
      
      {:ok, conversation_state, updated_state}
    end
  end
  
  defp process_conversation_message(conversation_id, message, user_context, state) do
    case Map.get(state.conversations, conversation_id) do
      nil ->
        {:error, :conversation_not_found}
        
      conversation ->
        with {:ok, classified_intent} <- classify_message_intent(message, conversation),
             {:ok, enhanced_context} <- build_conversation_context(conversation, user_context),
             {:ok, response, updated_conversation} <- 
               route_message_to_assistant(message, classified_intent, enhanced_context, conversation, state) do
          
          # Update conversation state
          updated_conversations = Map.put(state.conversations, conversation_id, updated_conversation)
          updated_state = %{state | conversations: updated_conversations}
          
          # Check if conversation needs summarization
          final_state = maybe_summarize_conversation(conversation_id, updated_state)
          
          {:ok, response, final_state}
        end
    end
  end
  
  defp finalize_conversation(conversation_id, state) do
    case Map.get(state.conversations, conversation_id) do
      nil ->
        {:error, :conversation_not_found}
        
      conversation ->
        # Generate final summary (gracefully handle failures)
        summary = case generate_conversation_summary(conversation_id, state) do
          {:ok, summary_data} -> summary_data
          {:error, _reason} -> %{
            conversation_id: conversation_id,
            summary: "Conversation ended without summary due to LLM unavailability",
            generated_at: DateTime.utc_now(),
            history_length: length(conversation.history),
            conversation_type: conversation.conversation_type
          }
        end
        
        # Store in conversation memory
        conversation_memory = Map.put(state.conversation_memory, conversation_id, %{
          summary: summary,
          ended_at: DateTime.utc_now(),
          metadata: conversation.metadata
        })
        
        # Remove from active conversations
        updated_conversations = Map.delete(state.conversations, conversation_id)
        
        updated_state = %{state | 
          conversations: updated_conversations,
          conversation_memory: conversation_memory
        }
        
        EventBus.publish("ai.coordinator.conversation_manager.conversation_ended", %{
          conversation_id: conversation_id,
          summary: summary,
          timestamp: DateTime.utc_now()
        })
        
        {:ok, updated_state}
    end
  end
  
  defp classify_message_intent(message, conversation) do
    # Enhanced intent classification based on message content and conversation context
    intent = cond do
      contains_coding_keywords?(message) -> :coding_request
      contains_question_keywords?(message) -> :information_request
      contains_bug_keywords?(message) -> :bug_report
      contains_feature_keywords?(message) -> :feature_request
      contains_explanation_keywords?(message) -> :explanation_request
      contains_review_keywords?(message) -> :review_request
      is_follow_up_message?(message, conversation) -> :follow_up
      true -> :general_conversation
    end
    
    confidence = calculate_intent_confidence(message, intent)
    
    {:ok, %{
      intent: intent,
      confidence: confidence,
      keywords: extract_relevant_keywords(message),
      context_clues: extract_context_clues(message, conversation)
    }}
  end
  
  defp build_conversation_context(conversation, user_context) do
    # Build comprehensive context for the assistant
    recent_history = Enum.take(conversation.history, -@context_window_size)
    
    context = %{
      conversation_id: conversation.conversation_id,
      conversation_type: conversation.conversation_type,
      recent_history: recent_history,
      full_context: conversation.context,
      user_context: user_context,
      turn_count: conversation.metadata.turn_count,
      last_activity: conversation.last_activity,
      current_intent: conversation.current_intent
    }
    
    {:ok, context}
  end
  
  defp route_message_to_assistant(message, classified_intent, context, conversation, state) do
    # Determine which assistant should handle this message
    assistant_type = determine_assistant_for_intent(classified_intent.intent, conversation)
    
    # Prepare request for the assistant
    request = %{
      type: map_intent_to_request_type(classified_intent.intent),
      message: message,
      intent: classified_intent,
      conversation_context: context
    }
    
    # Route to appropriate assistant
    case route_to_assistant(assistant_type, request, context, state) do
      {:ok, assistant_response} ->
        # Update conversation history
        user_turn = %{
          type: :user,
          content: message,
          timestamp: DateTime.utc_now(),
          intent: classified_intent
        }
        
        assistant_turn = %{
          type: :assistant,
          content: assistant_response.response,
          timestamp: DateTime.utc_now(),
          assistant: assistant_type,
          metadata: assistant_response
        }
        
        updated_history = conversation.history ++ [user_turn, assistant_turn]
        
        updated_conversation = %{conversation |
          history: updated_history,
          last_activity: DateTime.utc_now(),
          current_intent: classified_intent.intent,
          active_assistant: assistant_type,
          metadata: update_conversation_metadata(conversation.metadata, assistant_response)
        }
        
        {:ok, assistant_response, updated_conversation}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp route_to_assistant(:coding_assistant, request, context, state) do
    # Route to CodingAssistant
    case CodingAssistant.handle_request(request, context, %{}) do
      {:ok, response, _updated_context} ->
        {:ok, %{
          response: response.response || "I've processed your coding request.",
          artifacts: response.artifacts || %{},
          assistant_type: :coding_assistant,
          workflow: response.workflow,
          actions_taken: response.actions_taken || [],
          next_steps: response.next_steps || []
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp route_to_assistant(:general_assistant, request, context, _state) do
    # Handle general conversation through LLM
    conversation_prompt = generate_conversation_prompt(request, context)
    
    llm_request = %{
      type: :conversation,
      prompt: conversation_prompt,
      options: %{
        temperature: 0.7,
        max_tokens: 2000
      }
    }
    
    case ModelCoordinator.process_request(llm_request) do
      {:ok, llm_response} ->
        {:ok, %{
          response: llm_response,
          assistant_type: :general_assistant,
          conversation_turn: true
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp route_to_assistant(assistant_type, _request, _context, _state) do
    {:error, "Unknown assistant type: #{assistant_type}"}
  end
  
  defp generate_conversation_prompt(request, context) do
    recent_history = format_conversation_history(context.recent_history)
    
    """
    You are an AI assistant having a conversation. Here's the context:
    
    Conversation Type: #{context.conversation_type}
    Turn Count: #{context.turn_count}
    Current Intent: #{request.intent.intent}
    
    Recent Conversation History:
    #{recent_history}
    
    Current User Message: #{request.message}
    
    Please provide a helpful, contextually appropriate response. Consider the conversation history
    and maintain continuity with previous exchanges.
    """
  end
  
  defp format_conversation_history(history) do
    history
    |> Enum.map(fn turn ->
      case turn.type do
        :user -> "User: #{turn.content}"
        :assistant -> "Assistant: #{turn.content}"
      end
    end)
    |> Enum.join("\n")
  end
  
  defp maybe_summarize_conversation(conversation_id, state) do
    conversation = state.conversations[conversation_id]
    
    if length(conversation.history) > @summarization_threshold do
      case generate_and_store_summary(conversation_id, conversation, state) do
        {:ok, updated_state} ->
          # Trim conversation history
          trimmed_history = Enum.take(conversation.history, -@context_window_size)
          updated_conversation = %{conversation | history: trimmed_history}
          
          updated_conversations = Map.put(updated_state.conversations, conversation_id, updated_conversation)
          %{updated_state | conversations: updated_conversations}
          
        {:error, _reason} ->
          state
      end
    else
      state
    end
  end
  
  defp generate_and_store_summary(conversation_id, conversation, state) do
    case generate_conversation_summary(conversation_id, state) do
      {:ok, summary} ->
        updated_summaries = Map.put(state.conversation_summaries, conversation_id, summary)
        {:ok, %{state | conversation_summaries: updated_summaries}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp generate_conversation_summary(conversation_id, state) do
    case Map.get(state.conversations, conversation_id) do
      nil ->
        {:error, :conversation_not_found}
        
      conversation ->
        history_text = format_conversation_history(conversation.history)
        
        summary_prompt = """
        Please provide a concise summary of this conversation:
        
        Conversation Type: #{conversation.conversation_type}
        Started: #{conversation.started_at}
        Messages: #{length(conversation.history)}
        
        Conversation History:
        #{history_text}
        
        Summary should include:
        - Main topics discussed
        - Key decisions or outcomes
        - Important context for future reference
        - Any unresolved issues
        """
        
        llm_request = %{
          type: :summarization,
          prompt: summary_prompt,
          options: %{
            temperature: 0.3,
            max_tokens: 500
          }
        }
        
        case ModelCoordinator.process_request(llm_request) do
          {:ok, summary_text} ->
            summary = %{
              conversation_id: conversation_id,
              summary: summary_text,
              generated_at: DateTime.utc_now(),
              history_length: length(conversation.history),
              conversation_type: conversation.conversation_type
            }
            
            {:ok, summary}
            
          {:error, reason} ->
            {:error, reason}
        end
    end
  end
  
  defp clear_conversation_history_impl(conversation_id, preserve_last_n, state) do
    case Map.get(state.conversations, conversation_id) do
      nil ->
        {:error, :conversation_not_found}
        
      conversation ->
        # Generate summary before clearing
        {:ok, _summary} = generate_and_store_summary(conversation_id, conversation, state)
        
        # Keep only the last N messages
        preserved_history = Enum.take(conversation.history, -preserve_last_n)
        updated_conversation = %{conversation | history: preserved_history}
        
        updated_conversations = Map.put(state.conversations, conversation_id, updated_conversation)
        updated_state = %{state | conversations: updated_conversations}
        
        {:ok, updated_state}
    end
  end
  
  defp search_conversation_history_impl(conversation_id, query, limit, state) do
    case Map.get(state.conversations, conversation_id) do
      nil ->
        {:error, :conversation_not_found}
        
      conversation ->
        # Simple keyword-based search (could be enhanced with semantic search)
        query_words = String.downcase(query) |> String.split()
        
        matching_turns = conversation.history
        |> Enum.filter(fn turn ->
          content_words = String.downcase(turn.content) |> String.split()
          Enum.any?(query_words, fn query_word ->
            Enum.any?(content_words, &String.contains?(&1, query_word))
          end)
        end)
        |> Enum.take(limit)
        
        {:ok, matching_turns}
    end
  end
  
  defp handle_conversation_request(request, conversation_context, project_context, state) do
    # Handle requests through the Assistant interface
    conversation_id = Map.get(conversation_context, :conversation_id, generate_conversation_id())
    
    # Start conversation if it doesn't exist
    unless Map.has_key?(state.conversations, conversation_id) do
      conversation_type = determine_conversation_type(request)
      {:ok, _conversation, updated_state} = create_new_conversation(
        conversation_id, 
        conversation_type, 
        Map.merge(conversation_context, project_context), 
        state
      )
      state = updated_state
    end
    
    # Process the message
    message = Map.get(request, :message, Map.get(request, :content, ""))
    user_context = Map.merge(conversation_context, project_context)
    
    case process_conversation_message(conversation_id, message, user_context, state) do
      {:ok, response, updated_state} ->
        updated_context = Map.merge(conversation_context, %{
          conversation_id: conversation_id,
          last_response: response,
          updated_at: DateTime.utc_now()
        })
        
        {:ok, response, updated_context, updated_state}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Helper functions for intent classification
  
  defp contains_coding_keywords?(message) do
    coding_keywords = [
      "function", "def", "code", "implement", "refactor", "debug", 
      "test", "bug", "error", "syntax", "algorithm", "class", "module"
    ]
    
    message_lower = String.downcase(message)
    Enum.any?(coding_keywords, &String.contains?(message_lower, &1))
  end
  
  defp contains_question_keywords?(message) do
    question_keywords = ["how", "what", "why", "when", "where", "which", "explain"]
    message_lower = String.downcase(message)
    
    Enum.any?(question_keywords, &String.contains?(message_lower, &1)) or
      String.ends_with?(String.trim(message), "?")
  end
  
  defp contains_bug_keywords?(message) do
    bug_keywords = ["bug", "error", "crash", "exception", "broken", "fix", "issue"]
    message_lower = String.downcase(message)
    Enum.any?(bug_keywords, &String.contains?(message_lower, &1))
  end
  
  defp contains_feature_keywords?(message) do
    feature_keywords = ["add", "implement", "create", "build", "feature", "functionality"]
    message_lower = String.downcase(message)
    Enum.any?(feature_keywords, &String.contains?(message_lower, &1))
  end
  
  defp contains_explanation_keywords?(message) do
    explanation_keywords = ["explain", "understand", "how does", "what is", "tell me about"]
    message_lower = String.downcase(message)
    Enum.any?(explanation_keywords, &String.contains?(message_lower, &1))
  end
  
  defp contains_review_keywords?(message) do
    review_keywords = ["review", "check", "analyze", "look at", "examine"]
    message_lower = String.downcase(message)
    Enum.any?(review_keywords, &String.contains?(message_lower, &1))
  end
  
  defp is_follow_up_message?(message, conversation) do
    # Simple heuristic for follow-up detection
    follow_up_indicators = ["also", "and", "furthermore", "additionally", "next"]
    message_lower = String.downcase(message)
    
    has_follow_up_words = Enum.any?(follow_up_indicators, &String.contains?(message_lower, &1))
    is_short = String.length(String.trim(message)) < 50
    has_recent_activity = length(conversation.history) > 0
    
    (has_follow_up_words or is_short) and has_recent_activity
  end
  
  defp calculate_intent_confidence(message, intent) do
    # Simple confidence calculation based on keyword density
    base_confidence = 0.7
    
    keyword_density = case intent do
      :coding_request -> count_coding_keywords(message) / max(String.split(message) |> length(), 1)
      :bug_report -> count_bug_keywords(message) / max(String.split(message) |> length(), 1)
      _ -> 0.1
    end
    
    min(base_confidence + keyword_density * 0.3, 0.95)
  end
  
  defp count_coding_keywords(message) do
    coding_keywords = ["function", "def", "code", "implement", "refactor", "debug", "test", "bug"]
    message_lower = String.downcase(message)
    Enum.count(coding_keywords, &String.contains?(message_lower, &1))
  end
  
  defp count_bug_keywords(message) do
    bug_keywords = ["bug", "error", "crash", "exception", "broken", "fix", "issue"]
    message_lower = String.downcase(message)
    Enum.count(bug_keywords, &String.contains?(message_lower, &1))
  end
  
  defp extract_relevant_keywords(message) do
    # Extract important keywords for context
    words = String.split(String.downcase(message))
    
    # Filter out common words and return meaningful keywords
    stop_words = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"]
    
    words
    |> Enum.reject(&(&1 in stop_words))
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.take(10)
  end
  
  defp extract_context_clues(message, conversation) do
    # Extract contextual information that might be useful
    %{
      message_length: String.length(message),
      word_count: length(String.split(message)),
      has_code_snippets: String.contains?(message, "```") or String.contains?(message, "`"),
      mentions_files: String.contains?(message, ".ex") or String.contains?(message, ".exs"),
      conversation_length: length(conversation.history),
      conversation_type: conversation.conversation_type
    }
  end
  
  defp determine_initial_assistant(:coding_conversation), do: :coding_assistant
  defp determine_initial_assistant(:debugging_conversation), do: :coding_assistant
  defp determine_initial_assistant(_), do: :general_assistant
  
  defp determine_assistant_for_intent(:coding_request, _conversation), do: :coding_assistant
  defp determine_assistant_for_intent(:bug_report, _conversation), do: :coding_assistant
  defp determine_assistant_for_intent(:feature_request, _conversation), do: :coding_assistant
  defp determine_assistant_for_intent(:review_request, _conversation), do: :coding_assistant
  defp determine_assistant_for_intent(_, _conversation), do: :general_assistant
  
  defp map_intent_to_request_type(:coding_request), do: :coding_task
  defp map_intent_to_request_type(:bug_report), do: :bug_fix
  defp map_intent_to_request_type(:feature_request), do: :feature_request
  defp map_intent_to_request_type(:review_request), do: :code_review
  defp map_intent_to_request_type(_), do: :conversation
  
  defp determine_conversation_type(request) do
    cond do
      Map.get(request, :type) in [:coding_task, :bug_fix, :feature_request] -> :coding_conversation
      Map.get(request, :type) == :project_planning -> :planning_conversation
      String.contains?(to_string(Map.get(request, :message, "")), "learn") -> :learning_conversation
      true -> :general_conversation
    end
  end
  
  defp update_conversation_metadata(metadata, assistant_response) do
    %{metadata |
      turn_count: metadata.turn_count + 1,
      total_tokens: metadata.total_tokens + estimate_tokens(assistant_response),
      quality_score: calculate_quality_score(metadata, assistant_response)
    }
  end
  
  defp estimate_tokens(response) do
    # Simple token estimation
    content = Map.get(response, :response, "")
    String.split(content) |> length() |> Kernel.*(1.3) |> round()
  end
  
  defp calculate_quality_score(metadata, response) do
    # Simple quality score based on response completeness
    base_score = metadata.quality_score
    
    response_quality = cond do
      Map.has_key?(response, :artifacts) and map_size(response.artifacts) > 0 -> 5
      Map.has_key?(response, :actions_taken) and length(response.actions_taken) > 0 -> 3
      String.length(Map.get(response, :response, "")) > 50 -> 1
      true -> -2
    end
    
    max(min(base_score + response_quality, 100), 0)
  end
  
  defp initialize_assistants do
    %{
      coding_assistant: CodingAssistant,
      general_assistant: :llm_direct
    }
  end
  
  defp generate_session_id do
    "conversation_manager_" <> Base.encode16(:crypto.strong_rand_bytes(8))
  end
  
  defp generate_conversation_id do
    "conv_" <> Base.encode16(:crypto.strong_rand_bytes(6))
  end
end