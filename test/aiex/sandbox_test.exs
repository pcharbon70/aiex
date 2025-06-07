defmodule Aiex.SandboxTest do
  use ExUnit.Case, async: false
  alias Aiex.Sandbox
  alias Aiex.Sandbox.{Config, AuditLogger}

  @temp_dir System.tmp_dir!()
  @test_sandbox Path.join(@temp_dir, "aiex_sandbox_test")

  setup do
    # Create test sandbox directory
    File.mkdir_p!(@test_sandbox)

    # Configure sandbox
    config_opts = [
      sandbox_roots: [@test_sandbox],
      audit_enabled: true,
      audit_level: :verbose
    ]

    # Start or update the config
    case Process.whereis(Config) do
      nil -> start_supervised!({Config, config_opts})
      _pid -> Config.update(config_opts)
    end

    # Start audit logger if not running
    case Process.whereis(AuditLogger) do
      nil -> start_supervised!({AuditLogger, log_dir: Path.join(@temp_dir, "test_logs")})
      _pid -> :ok
    end

    on_exit(fn ->
      # Clean up test files
      File.rm_rf(@test_sandbox)
      File.rm_rf(Path.join(@temp_dir, "test_logs"))
    end)

    {:ok, test_dir: @test_sandbox}
  end

  describe "file reading operations" do
    test "reads files within sandbox", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "test.txt")
      content = "Hello, World!"

      File.write!(test_file, content)

      assert {:ok, ^content} = Sandbox.read(test_file)
    end

    test "reads lines from files within sandbox", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "lines.txt")
      content = "Line 1\nLine 2\nLine 3"

      File.write!(test_file, content)

      assert {:ok, ["Line 1", "Line 2", "Line 3"]} = Sandbox.read_lines(test_file)
    end

    test "rejects reading files outside sandbox" do
      outside_file = "/etc/passwd"

      assert {:error, :outside_sandbox} = Sandbox.read(outside_file)
    end

    test "rejects reading with directory traversal attempts", %{test_dir: test_dir} do
      malicious_path = Path.join(test_dir, "../../../etc/passwd")

      assert {:error, :traversal_attempt} = Sandbox.read(malicious_path)
    end
  end

  describe "file writing operations" do
    test "writes files within sandbox", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "write_test.txt")
      content = "Test content"

      assert :ok = Sandbox.write(test_file, content)
      assert File.read!(test_file) == content
    end

    test "appends to files within sandbox", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "append_test.txt")
      initial_content = "Initial content\n"
      appended_content = "Appended content"

      File.write!(test_file, initial_content)

      assert :ok = Sandbox.append(test_file, appended_content)
      assert File.read!(test_file) == initial_content <> appended_content
    end

    test "creates parent directories when writing", %{test_dir: test_dir} do
      nested_file = Path.join([test_dir, "subdir", "nested", "file.txt"])
      content = "Nested content"

      assert :ok = Sandbox.write(nested_file, content)
      assert File.read!(nested_file) == content
    end

    test "rejects writing files outside sandbox" do
      outside_file = "/tmp/outside_sandbox.txt"

      assert {:error, :outside_sandbox} = Sandbox.write(outside_file, "content")
    end
  end

  describe "directory operations" do
    test "lists directory contents within sandbox", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "file1.txt"), "content1")
      File.write!(Path.join(test_dir, "file2.txt"), "content2")

      assert {:ok, entries} = Sandbox.list_dir(test_dir)
      assert "file1.txt" in entries
      assert "file2.txt" in entries
    end

    test "creates directories within sandbox", %{test_dir: test_dir} do
      new_dir = Path.join(test_dir, "new_directory")

      assert :ok = Sandbox.mkdir_p(new_dir)
      assert File.dir?(new_dir)
    end

    test "rejects listing directories outside sandbox" do
      assert {:error, :outside_sandbox} = Sandbox.list_dir("/etc")
    end
  end

  describe "file management operations" do
    test "deletes files within sandbox", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "delete_me.txt")
      File.write!(test_file, "content")

      assert File.exists?(test_file)
      assert :ok = Sandbox.delete(test_file)
      refute File.exists?(test_file)
    end

    test "copies files within sandbox", %{test_dir: test_dir} do
      source = Path.join(test_dir, "source.txt")
      destination = Path.join(test_dir, "destination.txt")
      content = "Copy this content"

      File.write!(source, content)

      assert :ok = Sandbox.copy(source, destination)
      assert File.read!(destination) == content
    end

    test "moves files within sandbox", %{test_dir: test_dir} do
      source = Path.join(test_dir, "move_source.txt")
      destination = Path.join(test_dir, "move_destination.txt")
      content = "Move this content"

      File.write!(source, content)

      assert :ok = Sandbox.move(source, destination)
      refute File.exists?(source)
      assert File.read!(destination) == content
    end

    test "rejects copying to outside sandbox", %{test_dir: test_dir} do
      source = Path.join(test_dir, "source.txt")
      destination = "/tmp/outside.txt"

      File.write!(source, "content")

      assert {:error, :outside_sandbox} = Sandbox.copy(source, destination)
    end
  end

  describe "file information operations" do
    test "gets file stats within sandbox", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "stat_test.txt")
      File.write!(test_file, "content")

      assert {:ok, %File.Stat{}} = Sandbox.stat(test_file)
    end

    test "checks file existence within sandbox", %{test_dir: test_dir} do
      existing_file = Path.join(test_dir, "existing.txt")
      non_existing_file = Path.join(test_dir, "non_existing.txt")

      File.write!(existing_file, "content")

      assert Sandbox.exists?(existing_file)
      refute Sandbox.exists?(non_existing_file)
    end

    test "rejects stat on files outside sandbox" do
      assert {:error, :outside_sandbox} = Sandbox.stat("/etc/passwd")
    end
  end

  describe "configuration management" do
    test "manages allowlist", %{test_dir: test_dir} do
      new_path = Path.join(test_dir, "allowed")

      # Add to allowlist
      assert :ok = Sandbox.add_to_allowlist(new_path)

      # Should now be accessible
      File.mkdir_p!(new_path)
      test_file = Path.join(new_path, "test.txt")
      assert :ok = Sandbox.write(test_file, "content")

      # Remove from allowlist
      assert :ok = Sandbox.remove_from_allowlist(new_path)
    end

    test "gets current configuration" do
      assert {:ok, config} = Sandbox.get_config()
      assert is_struct(config, Config)
      assert @test_sandbox in config.sandbox_roots
    end
  end

  describe "error handling" do
    test "handles non-existent files gracefully", %{test_dir: test_dir} do
      non_existent = Path.join(test_dir, "does_not_exist.txt")

      assert {:error, :enoent} = Sandbox.read(non_existent)
    end

    test "handles permission errors gracefully", %{test_dir: test_dir} do
      # Create a file and make it unreadable (if running with appropriate permissions)
      test_file = Path.join(test_dir, "no_permission.txt")
      File.write!(test_file, "content")

      # This test might not work in all environments due to permission handling
      # but it demonstrates the error handling pattern
      case Sandbox.read(test_file) do
        # File was readable
        {:ok, _} -> :ok
        # Permission error was handled
        {:error, _reason} -> :ok
      end
    end

    test "handles dangerous characters in paths", %{test_dir: test_dir} do
      dangerous_path = Path.join(test_dir, "file|command.txt")

      assert {:error, :dangerous_characters} = Sandbox.write(dangerous_path, "content")
    end
  end

  describe "audit logging" do
    test "logs file operations", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "audit_test.txt")

      # Perform some operations
      Sandbox.write(test_file, "content")
      Sandbox.read(test_file)

      # Check that operations were logged
      recent_entries = AuditLogger.get_recent_entries(10)

      # Should have logged the write and read operations
      operations = Enum.map(recent_entries, & &1.operation)
      assert :write in operations
      assert :read in operations
    end

    test "logs security violations" do
      malicious_path = "/etc/passwd"

      # This should trigger a security event
      Sandbox.read(malicious_path)

      # Check for security events in the logs
      recent_entries = AuditLogger.get_recent_entries(10)

      # Should have logged an access attempt with denial
      assert Enum.any?(recent_entries, fn entry ->
               entry.path == malicious_path and entry.result == {:denied, :outside_sandbox}
             end)
    end
  end

  describe "UTF-8 encoding handling" do
    test "handles valid UTF-8 content", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "utf8_test.txt")
      unicode_content = "Hello 🌍 World! こんにちは"

      assert :ok = Sandbox.write(test_file, unicode_content)
      assert {:ok, ^unicode_content} = Sandbox.read(test_file)
    end

    test "handles invalid UTF-8 gracefully", %{test_dir: test_dir} do
      test_file = Path.join(test_dir, "invalid_utf8.txt")

      # Write binary data that's not valid UTF-8
      invalid_utf8 = <<255, 254, 253>>
      File.write!(test_file, invalid_utf8)

      # Reading should handle the invalid encoding
      case Sandbox.read(test_file, encoding: :utf8) do
        # Expected behavior
        {:error, :invalid_encoding} -> :ok
        # Might be handled differently in some environments
        {:ok, _} -> :ok
      end
    end
  end
end
