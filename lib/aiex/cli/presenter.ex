defmodule Aiex.CLI.Presenter do
  @moduledoc """
  Rich terminal output using Owl for colorized and interactive displays.
  """

  @doc """
  Present successful command results with rich formatting.
  """
  def present_success(result) do
    case result do
      {:message, text} ->
        Owl.IO.puts([Owl.Data.tag(text, :green)])

      {:info, title, details} ->
        Owl.IO.puts([
          Owl.Data.tag("✓ #{title}", [:green, :bright]),
          "\n",
          format_details(details)
        ])

      {:created, items} when is_list(items) ->
        Owl.IO.puts([Owl.Data.tag("✓ Created:", [:green, :bright])])

        Enum.each(items, fn item ->
          Owl.IO.puts(["  ", Owl.Data.tag("• #{item}", :cyan)])
        end)

      {:analysis, results} ->
        present_analysis_results(results)

      _ ->
        Owl.IO.puts([Owl.Data.tag("✓ Command completed successfully", :green)])
    end
  end

  @doc """
  Present error messages with appropriate formatting and suggestions.
  """
  def present_error(stage, reason) do
    error_prefix = Owl.Data.tag("✗ Error", [:red, :bright])
    stage_info = Owl.Data.tag("(#{stage})", :yellow)

    Owl.IO.puts([error_prefix, " ", stage_info, ": ", reason])

    case stage do
      :parse_error ->
        Owl.IO.puts([
          "\n",
          Owl.Data.tag("Tip:", [:blue, :bright]),
          " Use 'aiex help' to see available commands and options."
        ])

      :validation_error ->
        Owl.IO.puts([
          "\n",
          Owl.Data.tag("Tip:", [:blue, :bright]),
          " Check your command arguments and try again."
        ])

      :routing_error ->
        Owl.IO.puts([
          "\n",
          Owl.Data.tag("Available commands:", [:blue, :bright]),
          "\n  • create - Create new projects or modules",
          "\n  • analyze - Analyze code and dependencies",
          "\n  • help - Show help information",
          "\n  • version - Show version information"
        ])

      :execution_error ->
        Owl.IO.puts([
          "\n",
          Owl.Data.tag("Tip:", [:blue, :bright]),
          " The command failed during execution. Check the error message above."
        ])
    end
  end

  @doc """
  Show a progress bar for long-running operations.
  """
  def show_progress(title, fun) when is_function(fun, 1) do
    Owl.ProgressBar.start(
      id: :main,
      label: title,
      total: 100,
      timer: true
    )

    try do
      result =
        fun.(fn progress ->
          Owl.ProgressBar.inc(id: :main, step: progress)
        end)

      Owl.LiveScreen.await_render()
      result
    rescue
      e ->
        Owl.LiveScreen.await_render()
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Display an informational message with icon.
  """
  def info(message) do
    Owl.IO.puts([
      Owl.Data.tag("ℹ ", :blue),
      message
    ])
  end

  @doc """
  Display a warning message.
  """
  def warn(message) do
    Owl.IO.puts([
      Owl.Data.tag("⚠ ", :yellow),
      Owl.Data.tag(message, :yellow)
    ])
  end

  # Private helper functions

  defp format_details(details) when is_map(details) do
    details
    |> Enum.map(fn {key, value} ->
      ["  ", Owl.Data.tag("#{key}:", :cyan), " #{value}"]
    end)
    |> Enum.intersperse("\n")
  end

  defp format_details(details) when is_binary(details) do
    details
  end

  defp format_details(details) when is_list(details) do
    details
    |> Enum.map(fn item -> ["  • ", item] end)
    |> Enum.intersperse("\n")
  end

  defp present_analysis_results(results) do
    Owl.IO.puts([Owl.Data.tag("📊 Analysis Results:", [:blue, :bright])])

    Enum.each(results, fn
      {:file, path, issues} ->
        Owl.IO.puts(["\n", Owl.Data.tag("📄 #{path}", :cyan)])
        present_file_issues(issues)

      {:summary, summary} ->
        Owl.IO.puts(["\n", Owl.Data.tag("📋 Summary:", [:green, :bright])])
        format_details(summary) |> Owl.IO.puts()
    end)
  end

  defp present_file_issues(issues) do
    Enum.each(issues, fn
      {:warning, line, message} ->
        Owl.IO.puts([
          "  ",
          Owl.Data.tag("⚠", :yellow),
          " Line #{line}: #{message}"
        ])

      {:error, line, message} ->
        Owl.IO.puts([
          "  ",
          Owl.Data.tag("✗", :red),
          " Line #{line}: #{message}"
        ])

      {:suggestion, line, message} ->
        Owl.IO.puts([
          "  ",
          Owl.Data.tag("💡", :blue),
          " Line #{line}: #{message}"
        ])
    end)
  end
end
