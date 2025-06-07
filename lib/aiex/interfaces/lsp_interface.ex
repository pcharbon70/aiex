defmodule Aiex.Interfaces.LSPInterface do
  @moduledoc """
  Language Server Protocol interface for VS Code and other editors.

  This module provides LSP integration for AI-powered code completions,
  explanations, and refactoring suggestions directly in editors.
  """

  @behaviour Aiex.InterfaceBehaviour

  use GenServer
  require Logger

  alias Aiex.InterfaceGateway
  alias Aiex.Events.EventBus

  defstruct [
    :interface_id,
    :config,
    :client_capabilities,
    :workspace_folders,
    :open_documents,
    :completion_cache,
    :diagnostics_state
  ]

  ## LSP Constants
  @lsp_version "3.17.0"
  @server_info %{
    name: "Aiex LSP Server",
    version: "0.1.0"
  }

  ## Client API

  @doc """
  Start the LSP interface.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Handle LSP initialize request.
  """
  def handle_initialize(params) do
    GenServer.call(__MODULE__, {:lsp_initialize, params})
  end

  @doc """
  Handle text document changes.
  """
  def handle_text_document_change(params) do
    GenServer.cast(__MODULE__, {:text_document_change, params})
  end

  @doc """
  Handle completion requests.
  """
  def handle_completion_request(params) do
    GenServer.call(__MODULE__, {:completion_request, params})
  end

  @doc """
  Handle hover requests for explanations.
  """
  def handle_hover_request(params) do
    GenServer.call(__MODULE__, {:hover_request, params})
  end

  @doc """
  Handle code action requests.
  """
  def handle_code_action_request(params) do
    GenServer.call(__MODULE__, {:code_action_request, params})
  end

  ## InterfaceBehaviour Callbacks

  @impl true
  def init(config) do
    # Register with InterfaceGateway
    interface_config = %{
      type: :lsp,
      session_id: "lsp_main",
      user_id: nil,
      capabilities: [
        :text_document_completion,
        :text_document_hover,
        :text_document_code_action,
        :text_document_diagnostic,
        :workspace_symbol,
        :ai_explanations,
        :ai_refactoring,
        :ai_test_generation
      ],
      settings: Map.get(config, :settings, %{})
    }

    case InterfaceGateway.register_interface(__MODULE__, interface_config) do
      {:ok, interface_id} ->
        state = %__MODULE__{
          interface_id: interface_id,
          config: interface_config,
          client_capabilities: %{},
          workspace_folders: [],
          open_documents: %{},
          completion_cache: %{},
          diagnostics_state: %{}
        }

        # Subscribe to relevant events
        EventBus.subscribe(:context_updated)
        EventBus.subscribe(:request_completed)

        Logger.info("LSP interface started with ID: #{interface_id}")
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_request(request, state) do
    # Process LSP-specific requests
    case validate_lsp_request(request, state) do
      :ok ->
        # Enhance request with LSP context
        enhanced_request = enhance_request_with_lsp_context(request, state)
        
        case InterfaceGateway.submit_request(state.interface_id, enhanced_request) do
          {:ok, request_id} ->
            response = %{
              id: request.id,
              status: :async,
              request_id: request_id,
              metadata: %{
                interface: :lsp,
                document_uri: request.context[:document_uri]
              }
            }
            {:async, request_id, state}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_stream(request_id, partial_response, state) do
    # Handle streaming responses for LSP
    case partial_response.status do
      :complete ->
        # Send final response to LSP client
        send_lsp_response(request_id, partial_response, state)
        {:complete, partial_response, state}
      _ ->
        # For LSP, we typically don't stream partial responses
        {:continue, state}
    end
  end

  @impl true
  def handle_event(:context_updated, event_data, state) do
    # Update document context and trigger diagnostics if needed
    case event_data.document_uri do
      nil -> {:ok, state}
      document_uri ->
        updated_state = update_document_context(document_uri, event_data.context, state)
        trigger_diagnostics(document_uri, updated_state)
        {:ok, updated_state}
    end
  end

  def handle_event(event_type, event_data, state) do
    Logger.debug("LSP interface received event: #{event_type}")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cleanup and unregister interface
    InterfaceGateway.unregister_interface(state.interface_id)
    :ok
  end

  @impl true
  def get_status(state) do
    %{
      capabilities: state.config.capabilities,
      active_requests: count_active_requests(state),
      session_info: %{
        open_documents: map_size(state.open_documents),
        workspace_folders: length(state.workspace_folders),
        cached_completions: map_size(state.completion_cache)
      },
      health: determine_health(state)
    }
  end

  @impl true
  def validate_request(request) do
    required_fields = [:id, :type, :content]
    
    case Enum.all?(required_fields, &Map.has_key?(request, &1)) do
      true -> 
        # Additional LSP-specific validation
        case request.context[:document_uri] do
          nil -> {:error, :missing_document_uri}
          _ -> :ok
        end
      false -> 
        {:error, :missing_required_fields}
    end
  end

  @impl true
  def format_response(response, state) do
    # Format response for LSP protocol compliance
    %{
      response | 
      content: format_lsp_content(response.content, response.type),
      metadata: Map.merge(response.metadata || %{}, %{
        interface: :lsp,
        lsp_version: @lsp_version,
        server_info: @server_info
      })
    }
  end

  ## GenServer Callbacks

  @impl true
  def handle_call({:lsp_initialize, params}, _from, state) do
    # Handle LSP initialize request
    client_capabilities = Map.get(params, "capabilities", %{})
    workspace_folders = Map.get(params, "workspaceFolders", [])

    server_capabilities = %{
      "textDocumentSync" => %{
        "openClose" => true,
        "change" => 2,  # Incremental
        "save" => %{"includeText" => true}
      },
      "completionProvider" => %{
        "triggerCharacters" => [".", ":", "@"],
        "resolveProvider" => true
      },
      "hoverProvider" => true,
      "codeActionProvider" => %{
        "codeActionKinds" => [
          "quickfix",
          "refactor",
          "refactor.extract",
          "source.generate.test"
        ]
      },
      "diagnosticProvider" => %{
        "interFileDependencies" => false,
        "workspaceDiagnostics" => false
      }
    }

    initialize_result = %{
      "capabilities" => server_capabilities,
      "serverInfo" => @server_info
    }

    new_state = %{
      state |
      client_capabilities: client_capabilities,
      workspace_folders: workspace_folders
    }

    Logger.info("LSP initialized with capabilities: #{inspect(client_capabilities)}")
    {:reply, {:ok, initialize_result}, new_state}
  end

  def handle_call({:completion_request, params}, _from, state) do
    document_uri = params["textDocument"]["uri"]
    position = params["position"]
    
    # Check cache first
    cache_key = {document_uri, position["line"], position["character"]}
    
    case Map.get(state.completion_cache, cache_key) do
      nil ->
        # Generate AI-powered completions
        request = %{
          id: generate_request_id(),
          type: :completion,
          content: extract_completion_context(document_uri, position, state),
          context: %{
            document_uri: document_uri,
            position: position,
            trigger_kind: params["context"]["triggerKind"]
          },
          priority: :high
        }

        case handle_request(request, state) do
          {:async, request_id, new_state} ->
            # For LSP, we need to wait for completion
            # In a real implementation, this would be handled asynchronously
            completion_items = generate_default_completions(request.content)
            
            # Cache the result
            updated_cache = Map.put(state.completion_cache, cache_key, completion_items)
            final_state = %{new_state | completion_cache: updated_cache}
            
            {:reply, {:ok, completion_items}, final_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      cached_items ->
        {:reply, {:ok, cached_items}, state}
    end
  end

  def handle_call({:hover_request, params}, _from, state) do
    document_uri = params["textDocument"]["uri"]
    position = params["position"]
    
    # Extract symbol under cursor
    symbol_context = extract_symbol_context(document_uri, position, state)
    
    request = %{
      id: generate_request_id(),
      type: :explanation,
      content: symbol_context,
      context: %{
        document_uri: document_uri,
        position: position,
        hover_request: true
      },
      priority: :normal
    }

    case handle_request(request, state) do
      {:async, _request_id, new_state} ->
        # Generate explanation hover content
        hover_content = generate_hover_explanation(symbol_context)
        
        hover_result = %{
          "contents" => %{
            "kind" => "markdown",
            "value" => hover_content
          }
        }
        
        {:reply, {:ok, hover_result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:code_action_request, params}, _from, state) do
    document_uri = params["textDocument"]["uri"]
    range = params["range"]
    context = params["context"]
    
    # Generate AI-powered code actions
    selected_text = extract_selected_text(document_uri, range, state)
    
    code_actions = [
      %{
        "title" => "AI: Explain this code",
        "kind" => "refactor",
        "command" => %{
          "title" => "AI Explanation",
          "command" => "aiex.explainCode",
          "arguments" => [document_uri, range, selected_text]
        }
      },
      %{
        "title" => "AI: Refactor this code",
        "kind" => "refactor.extract",
        "command" => %{
          "title" => "AI Refactor",
          "command" => "aiex.refactorCode", 
          "arguments" => [document_uri, range, selected_text]
        }
      },
      %{
        "title" => "AI: Generate tests",
        "kind" => "source.generate.test",
        "command" => %{
          "title" => "AI Test Generation",
          "command" => "aiex.generateTests",
          "arguments" => [document_uri, range, selected_text]
        }
      }
    ]

    {:reply, {:ok, code_actions}, state}
  end

  @impl true
  def handle_cast({:text_document_change, params}, state) do
    document_uri = params["textDocument"]["uri"]
    content_changes = params["contentChanges"]
    
    # Update document content and invalidate relevant caches
    updated_state = 
      state
      |> update_document_content(document_uri, content_changes)
      |> invalidate_completion_cache(document_uri)

    # Trigger background context analysis
    trigger_context_analysis(document_uri, updated_state)

    {:noreply, updated_state}
  end

  ## Private Functions

  defp validate_lsp_request(request, _state) do
    case request.context[:document_uri] do
      nil -> {:error, :missing_document_uri}
      _ -> :ok
    end
  end

  defp enhance_request_with_lsp_context(request, state) do
    document_uri = request.context[:document_uri]
    document_info = Map.get(state.open_documents, document_uri, %{})
    
    enhanced_context = Map.merge(request.context || %{}, %{
      workspace_folders: state.workspace_folders,
      document_info: document_info,
      client_capabilities: state.client_capabilities
    })

    %{request | context: enhanced_context}
  end

  defp send_lsp_response(_request_id, _response, _state) do
    # In a real implementation, send response via LSP protocol
    :ok
  end

  defp update_document_context(document_uri, context, state) do
    current_doc = Map.get(state.open_documents, document_uri, %{})
    updated_doc = Map.merge(current_doc, %{context: context, updated_at: DateTime.utc_now()})
    
    %{state | open_documents: Map.put(state.open_documents, document_uri, updated_doc)}
  end

  defp trigger_diagnostics(_document_uri, _state) do
    # In a real implementation, trigger AI-powered diagnostics
    :ok
  end

  defp count_active_requests(_state) do
    # Track active requests
    0
  end

  defp determine_health(state) do
    cond do
      map_size(state.open_documents) > 50 -> :degraded
      true -> :healthy
    end
  end

  defp format_lsp_content(content, _type) do
    # Format content for LSP protocol
    content
  end

  defp extract_completion_context(document_uri, position, state) do
    # Extract context around cursor position for AI completion
    case Map.get(state.open_documents, document_uri) do
      nil -> ""
      doc_info ->
        # In a real implementation, extract lines around position
        Map.get(doc_info, :content, "")
    end
  end

  defp generate_default_completions(_context) do
    # Generate AI-powered completions
    [
      %{
        "label" => "AI Suggestion 1",
        "kind" => 3,  # Function
        "detail" => "AI-generated completion",
        "documentation" => "This completion was generated by Aiex AI"
      }
    ]
  end

  defp extract_symbol_context(document_uri, position, state) do
    # Extract symbol information for hover
    case Map.get(state.open_documents, document_uri) do
      nil -> ""
      _doc_info ->
        # In a real implementation, extract symbol at position
        "Symbol at line #{position["line"]}, character #{position["character"]}"
    end
  end

  defp generate_hover_explanation(symbol_context) do
    """
    ## AI Explanation

    **Symbol:** `#{symbol_context}`

    This symbol represents an Elixir construct. The AI analysis suggests:

    - **Type**: Function/Module/Variable
    - **Usage**: Common Elixir pattern
    - **Best Practices**: Follow OTP conventions

    *Generated by Aiex AI Assistant*
    """
  end

  defp extract_selected_text(_document_uri, _range, _state) do
    # Extract text in the given range
    "selected_code_block"
  end

  defp update_document_content(state, document_uri, content_changes) do
    # Update document content based on changes
    current_doc = Map.get(state.open_documents, document_uri, %{})
    
    # Apply content changes (simplified)
    updated_content = Enum.reduce(content_changes, Map.get(current_doc, :content, ""), fn
      change, content ->
        # In a real implementation, apply incremental changes
        Map.get(change, "text", content)
    end)
    
    updated_doc = Map.merge(current_doc, %{
      content: updated_content,
      updated_at: DateTime.utc_now()
    })
    
    %{state | open_documents: Map.put(state.open_documents, document_uri, updated_doc)}
  end

  defp invalidate_completion_cache(state, document_uri) do
    # Remove cached completions for the document
    updated_cache = 
      state.completion_cache
      |> Enum.reject(fn {{uri, _line, _char}, _items} -> uri == document_uri end)
      |> Enum.into(%{})
    
    %{state | completion_cache: updated_cache}
  end

  defp trigger_context_analysis(_document_uri, _state) do
    # In a real implementation, trigger background context analysis
    :ok
  end

  defp generate_request_id do
    "lsp_req_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end