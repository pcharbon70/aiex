defmodule Aiex.TUI.State do
  @moduledoc """
  TUI application state following TEA (The Elm Architecture) pattern.
  
  Manages the complete state of the terminal interface including chat history,
  context information, UI focus, and panel visibility.
  """
  
  defstruct [
    # Interface integration
    :interface_id,
    
    # Chat and conversation
    :messages,
    :current_input,
    :conversation_id,
    
    # Context and project state
    :project_context,
    :file_context,
    :recent_files,
    
    # UI state
    :active_panel,
    :panels_visible,
    :focus_state,
    :layout_mode,
    
    # Status and notifications
    :status_message,
    :notifications,
    :progress_indicator,
    
    # Performance and metrics
    :last_update,
    :render_time,
    :message_count,
    
    # Settings
    :theme,
    :keybindings,
    :preferences
  ]
  
  @type t :: %__MODULE__{
    interface_id: atom() | nil,
    messages: [Message.t()],
    current_input: String.t(),
    conversation_id: String.t() | nil,
    project_context: map(),
    file_context: map(),
    recent_files: [String.t()],
    active_panel: atom(),
    panels_visible: %{atom() => boolean()},
    focus_state: atom(),
    layout_mode: atom(),
    status_message: String.t() | nil,
    notifications: [Notification.t()],
    progress_indicator: map() | nil,
    last_update: DateTime.t(),
    render_time: integer(),
    message_count: integer(),
    theme: atom(),
    keybindings: map(),
    preferences: map()
  }
  
  defmodule Message do
    @moduledoc "Chat message structure"
    
    defstruct [
      :id,
      :role,        # :user, :assistant, :system, :error
      :content,
      :timestamp,
      :metadata,
      :tokens_used,
      :response_time
    ]
    
    @type t :: %__MODULE__{
      id: String.t(),
      role: atom(),
      content: String.t(),
      timestamp: DateTime.t(),
      metadata: map(),
      tokens_used: integer() | nil,
      response_time: integer() | nil
    }
  end
  
  defmodule Notification do
    @moduledoc "UI notification structure"
    
    defstruct [
      :id,
      :type,        # :info, :warning, :error, :success
      :message,
      :timestamp,
      :duration,
      :actions
    ]
    
    @type t :: %__MODULE__{
      id: String.t(),
      type: atom(),
      message: String.t(),
      timestamp: DateTime.t(),
      duration: integer(),
      actions: [map()]
    }
  end
  
  ## State creation and manipulation
  
  @doc """
  Creates a new initial TUI state.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      interface_id: nil,
      messages: [],
      current_input: "",
      conversation_id: nil,
      project_context: %{},
      file_context: %{},
      recent_files: [],
      active_panel: :conversation,
      panels_visible: %{
        conversation: true,
        context: true,
        status: true,
        actions: false
      },
      focus_state: :input,
      layout_mode: :chat_focused,
      status_message: "Aiex TUI Ready",
      notifications: [],
      progress_indicator: nil,
      last_update: DateTime.utc_now(),
      render_time: 0,
      message_count: 0,
      theme: :default,
      keybindings: default_keybindings(),
      preferences: default_preferences()
    }
  end
  
  @doc """
  Adds a new message to the chat history.
  """
  @spec add_message(t(), atom(), String.t(), map()) :: t()
  def add_message(state, role, content, metadata \\ %{}) do
    message = %Message{
      id: generate_message_id(),
      role: role,
      content: content,
      timestamp: DateTime.utc_now(),
      metadata: metadata,
      tokens_used: Map.get(metadata, :tokens_used),
      response_time: Map.get(metadata, :response_time)
    }
    
    %{state | 
      messages: state.messages ++ [message],
      message_count: state.message_count + 1,
      last_update: DateTime.utc_now()
    }
  end
  
  @doc """
  Updates the current input text.
  """
  @spec update_input(t(), String.t()) :: t()
  def update_input(state, input) do
    %{state | current_input: input, last_update: DateTime.utc_now()}
  end
  
  @doc """
  Clears the current input.
  """
  @spec clear_input(t()) :: t()
  def clear_input(state) do
    %{state | current_input: "", last_update: DateTime.utc_now()}
  end
  
  @doc """
  Updates the status message.
  """
  @spec set_status(t(), String.t()) :: t()
  def set_status(state, message) do
    %{state | status_message: message, last_update: DateTime.utc_now()}
  end
  
  @doc """
  Adds a notification.
  """
  @spec add_notification(t(), atom(), String.t(), integer()) :: t()
  def add_notification(state, type, message, duration \\ 5000) do
    notification = %Notification{
      id: generate_notification_id(),
      type: type,
      message: message,
      timestamp: DateTime.utc_now(),
      duration: duration,
      actions: []
    }
    
    %{state | 
      notifications: state.notifications ++ [notification],
      last_update: DateTime.utc_now()
    }
  end
  
  @doc """
  Toggles panel visibility.
  """
  @spec toggle_panel(t(), atom()) :: t()
  def toggle_panel(state, panel) do
    current_visibility = Map.get(state.panels_visible, panel, false)
    new_panels = Map.put(state.panels_visible, panel, !current_visibility)
    
    %{state | panels_visible: new_panels, last_update: DateTime.utc_now()}
  end
  
  @doc """
  Sets the active panel.
  """
  @spec set_active_panel(t(), atom()) :: t()
  def set_active_panel(state, panel) do
    %{state | active_panel: panel, last_update: DateTime.utc_now()}
  end
  
  @doc """
  Updates project context.
  """
  @spec update_project_context(t(), map()) :: t()
  def update_project_context(state, context) do
    %{state | project_context: context, last_update: DateTime.utc_now()}
  end
  
  @doc """
  Updates file context.
  """
  @spec update_file_context(t(), map()) :: t()
  def update_file_context(state, context) do
    %{state | file_context: context, last_update: DateTime.utc_now()}
  end
  
  ## Private functions
  
  defp generate_message_id do
    "msg_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
  
  defp generate_notification_id do
    "notif_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower))
  end
  
  defp default_keybindings do
    %{
      # Navigation
      tab: :next_panel,
      shift_tab: :prev_panel,
      ctrl_c: :quit,
      ctrl_q: :quit,
      
      # Panel toggles
      f1: :toggle_context_panel,
      f2: :toggle_actions_panel,
      
      # Input handling
      enter: :send_message,
      ctrl_enter: :send_message,
      escape: :clear_input,
      
      # Quick actions
      ctrl_n: :new_conversation,
      ctrl_s: :save_conversation,
      ctrl_l: :clear_conversation
    }
  end
  
  defp default_preferences do
    %{
      auto_scroll: true,
      show_timestamps: true,
      show_token_count: true,
      syntax_highlighting: true,
      word_wrap: true,
      max_history: 1000,
      notification_duration: 5000
    }
  end
end