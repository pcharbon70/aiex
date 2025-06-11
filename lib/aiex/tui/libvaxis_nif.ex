defmodule Aiex.Tui.LibvaxisNif do
  @moduledoc """
  Native Implemented Functions (NIFs) for Libvaxis terminal UI integration.
  
  This module provides the Zig/Libvaxis bridge for terminal user interface
  functionality, integrated directly into the BEAM VM via Zigler NIFs.
  """
  
  use Zig, 
    otp_app: :aiex,
    resources: [:VaxisInstance],
    nifs: [
      init_vaxis: [:dirty_io],
      cleanup_vaxis: [:dirty_io],
      start_event_loop: [:dirty_io],
      render_chat_layout: [:dirty_io],
      handle_input: [:dirty_io],
      get_terminal_size: [:dirty_io]
    ]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");
  const vaxis = @import("vaxis");
  
  // Resource type for managing Vaxis state
  const VaxisState = struct {
      vx: *vaxis.Vaxis,
      tty: *vaxis.Tty,
      loop: *vaxis.Loop,
      allocator: std.mem.Allocator,
      callback_pid: beam.pid,
      // Thread safety
      mutex: std.Thread.Mutex,
      render_pending: bool,
      should_exit: bool,
  };
  
  // Resource callbacks
  pub const VaxisInstance = beam.Resource(VaxisState, @import("root"), .{
      .Callbacks = .{
          .destructor = cleanup_vaxis_resource,
      }
  });
  
  /// Initialize Vaxis terminal interface
  pub fn init_vaxis(callback_pid: beam.pid) !beam.term {
      var gpa = std.heap.GeneralPurposeAllocator(.{}){};
      const allocator = gpa.allocator();
      
      // Initialize TTY
      var tty = try vaxis.Tty.init();
      errdefer tty.deinit();
      
      // Initialize Vaxis
      var vx = try vaxis.init(allocator, .{});
      errdefer vx.deinit(allocator, tty.anyWriter());
      
      // Create state
      const state = VaxisState{
          .vx = &vx,
          .tty = &tty,
          .allocator = allocator,
          .callback_pid = callback_pid,
          .mutex = std.Thread.Mutex{},
          .render_pending = false,
          .should_exit = false,
      };
      
      // Create resource
      const resource = try VaxisInstance.create(state, .{});
      
      return beam.make(resource, .{});
  }
  
  /// Cleanup Vaxis resources
  fn cleanup_vaxis_resource(state: *VaxisState) void {
      state.mutex.lock();
      defer state.mutex.unlock();
      
      state.should_exit = true;
      state.vx.deinit(state.allocator, state.tty.anyWriter());
      state.tty.deinit();
  }
  
  /// Start the event loop in a background thread
  pub fn start_event_loop(resource: beam.term) !beam.term {
      const vaxis_resource = try beam.get(VaxisInstance, resource, .{});
      const state = vaxis_resource.unpack();
      
      // Initialize event loop
      var loop: vaxis.Loop = .{
          .tty = state.tty,
          .vaxis = state.vx,
      };
      try loop.init();
      defer loop.deinit();
      
      try loop.start();
      state.loop = &loop;
      
      // Spawn event worker thread
      const thread = try std.Thread.spawn(.{}, event_worker, .{state});
      thread.detach();
      
      return beam.make_atom("ok");
  }
  
  /// Event worker thread
  fn event_worker(state: *VaxisState) void {
      while (true) {
          state.mutex.lock();
          const should_exit = state.should_exit;
          state.mutex.unlock();
          
          if (should_exit) break;
          
          const event = state.loop.nextEvent();
          
          // Convert Vaxis events to Elixir terms
          const elixir_event = switch (event) {
              .key_press => |key| beam.make(.{
                  .key_press, .{
                      .codepoint = key.codepoint,
                      .modifiers = .{
                          .ctrl = key.mods.ctrl,
                          .alt = key.mods.alt,
                          .shift = key.mods.shift,
                      },
                  }
              }, .{}),
              .mouse => |m| beam.make(.{
                  .mouse, .{
                      .x = m.col,
                      .y = m.row,
                      .button = m.button,
                      .type = m.type,
                  }
              }, .{}),
              .winsize => |ws| beam.make(.{
                  .resize, ws.cols, ws.rows
              }, .{}),
              else => beam.make(.{.unknown_event}, .{}),
          };
          
          // Send to Elixir process
          beam.send(state.callback_pid, elixir_event, .{}) catch break;
      }
  }
  
  /// Render chat layout
  pub fn render_chat_layout(
      resource: beam.term,
      messages: beam.term,
      input: beam.term,
      status: beam.term
  ) !beam.term {
      const vaxis_resource = try beam.get(VaxisInstance, resource, .{});
      const state = vaxis_resource.unpack();
      
      // Lock for thread safety
      state.mutex.lock();
      defer state.mutex.unlock();
      
      // Get window
      const win = state.vx.window();
      win.clear();
      
      // TODO: Implement actual rendering logic
      // For now, just return ok
      
      return beam.make_atom("ok");
  }
  
  /// Handle input key
  pub fn handle_input(resource: beam.term, key_event: beam.term) !beam.term {
      const vaxis_resource = try beam.get(VaxisInstance, resource, .{});
      const state = vaxis_resource.unpack();
      
      // TODO: Implement input handling
      
      return beam.make_atom("ok");
  }
  
  /// Get terminal size
  pub fn get_terminal_size(resource: beam.term) !beam.term {
      const vaxis_resource = try beam.get(VaxisInstance, resource, .{});
      const state = vaxis_resource.unpack();
      
      const win = state.vx.window();
      
      return beam.make(.{
          .ok, .{
              .width = win.width,
              .height = win.height,
          }
      }, .{});
  }
  """
  
  # Elixir API functions
  
  @doc """
  Initialize the Vaxis terminal interface.
  
  Returns `{:ok, resource}` on success or `{:error, reason}` on failure.
  """
  @spec init() :: {:ok, term()} | {:error, term()}
  def init do
    case init_vaxis(self()) do
      {:error, _} = error -> error
      resource -> {:ok, resource}
    end
  end
  
  @doc """
  Start the event loop for handling terminal events.
  """
  @spec start_event_loop(term()) :: :ok | {:error, term()}
  def start_event_loop(resource) do
    case start_event_loop_nif(resource) do
      :ok -> :ok
      error -> {:error, error}
    end
  end
  
  @doc """
  Render the chat layout with messages, input, and status.
  """
  @spec render(term(), list(), String.t(), map()) :: :ok | {:error, term()}
  def render(resource, messages, input, status) do
    case render_chat_layout(resource, messages, input, status) do
      :ok -> :ok
      error -> {:error, error}
    end
  end
  
  @doc """
  Get the current terminal size.
  """
  @spec terminal_size(term()) :: {:ok, {width :: integer(), height :: integer()}} | {:error, term()}
  def terminal_size(resource) do
    get_terminal_size(resource)
  end
  
  # NIF stubs (replaced by Zig implementation)
  defp init_vaxis(_pid), do: :erlang.nif_error(:not_loaded)
  defp start_event_loop_nif(_resource), do: :erlang.nif_error(:not_loaded)
  defp render_chat_layout(_resource, _messages, _input, _status), do: :erlang.nif_error(:not_loaded)
  defp handle_input(_resource, _key_event), do: :erlang.nif_error(:not_loaded)
  defp get_terminal_size(_resource), do: :erlang.nif_error(:not_loaded)
end