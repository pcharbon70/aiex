defmodule Aiex.Sandbox.PathValidatorTest do
  use ExUnit.Case, async: true
  alias Aiex.Sandbox.PathValidator

  describe "validate_path/2" do
    test "accepts valid paths within sandbox" do
      sandbox_root = "/tmp/sandbox"
      opts = [sandbox_roots: [sandbox_root]]

      assert {:ok, "/tmp/sandbox/file.txt"} =
               PathValidator.validate_path("/tmp/sandbox/file.txt", opts)

      assert {:ok, "/tmp/sandbox/subdir/file.txt"} =
               PathValidator.validate_path("/tmp/sandbox/subdir/file.txt", opts)
    end

    test "rejects paths outside sandbox" do
      opts = [sandbox_roots: ["/tmp/sandbox"]]

      assert {:error, :outside_sandbox} =
               PathValidator.validate_path("/etc/passwd", opts)

      assert {:error, :outside_sandbox} =
               PathValidator.validate_path("/tmp/other/file.txt", opts)
    end

    test "detects directory traversal attempts" do
      opts = [sandbox_roots: ["/tmp/sandbox"]]

      assert {:error, :traversal_attempt} =
               PathValidator.validate_path("/tmp/sandbox/../../../etc/passwd", opts)

      assert {:error, :traversal_attempt} =
               PathValidator.validate_path("/tmp/sandbox/./../../etc/passwd", opts)

      assert {:error, :traversal_attempt} =
               PathValidator.validate_path("/tmp/sandbox/subdir/../../../outside", opts)
    end

    test "detects URL-encoded traversal attempts" do
      opts = [sandbox_roots: ["/tmp/sandbox"]]

      assert {:error, :traversal_attempt} =
               PathValidator.validate_path("/tmp/sandbox/%2e%2e/etc/passwd", opts)

      assert {:error, :traversal_attempt} =
               PathValidator.validate_path("/tmp/sandbox/%252e%252e/etc/passwd", opts)
    end

    test "rejects paths with dangerous characters" do
      opts = [sandbox_roots: ["/tmp/sandbox"]]

      # Null byte is caught by traversal check first
      assert {:error, :traversal_attempt} =
               PathValidator.validate_path("/tmp/sandbox/file\x00.txt", opts)

      assert {:error, :dangerous_characters} =
               PathValidator.validate_path("/tmp/sandbox/file|command.txt", opts)

      assert {:error, :dangerous_characters} =
               PathValidator.validate_path("/tmp/sandbox/file;rm -rf.txt", opts)

      assert {:error, :dangerous_characters} =
               PathValidator.validate_path("/tmp/sandbox/file`whoami`.txt", opts)
    end

    test "handles multiple sandbox roots" do
      opts = [sandbox_roots: ["/tmp/sandbox1", "/home/user/sandbox2"]]

      assert {:ok, "/tmp/sandbox1/file.txt"} =
               PathValidator.validate_path("/tmp/sandbox1/file.txt", opts)

      assert {:ok, "/home/user/sandbox2/file.txt"} =
               PathValidator.validate_path("/home/user/sandbox2/file.txt", opts)

      assert {:error, :outside_sandbox} =
               PathValidator.validate_path("/tmp/sandbox2/file.txt", opts)
    end

    test "allows paths when no sandbox is configured" do
      assert {:ok, _} = PathValidator.validate_path("/any/path/file.txt", [])
    end
  end

  describe "within_sandbox?/2" do
    test "correctly identifies paths within sandbox" do
      assert PathValidator.within_sandbox?("/tmp/sandbox/file.txt", "/tmp/sandbox")
      assert PathValidator.within_sandbox?("/tmp/sandbox/sub/file.txt", "/tmp/sandbox")
      assert PathValidator.within_sandbox?("/tmp/sandbox", "/tmp/sandbox")

      refute PathValidator.within_sandbox?("/tmp/other/file.txt", "/tmp/sandbox")
      refute PathValidator.within_sandbox?("/tmp", "/tmp/sandbox")
      refute PathValidator.within_sandbox?("/tmp/sandboxother/file.txt", "/tmp/sandbox")
    end

    test "works with multiple sandbox roots" do
      roots = ["/tmp/sandbox1", "/home/user/sandbox2"]

      assert PathValidator.within_sandbox?("/tmp/sandbox1/file.txt", roots)
      assert PathValidator.within_sandbox?("/home/user/sandbox2/file.txt", roots)

      refute PathValidator.within_sandbox?("/tmp/sandbox3/file.txt", roots)
    end
  end

  describe "contains_traversal?/1" do
    test "detects various traversal patterns" do
      assert PathValidator.contains_traversal?("../etc/passwd")
      assert PathValidator.contains_traversal?("../../etc/passwd")
      assert PathValidator.contains_traversal?("subdir/../../../etc/passwd")
      assert PathValidator.contains_traversal?("subdir/./../../etc/passwd")
      assert PathValidator.contains_traversal?("%2e%2e/etc/passwd")
      assert PathValidator.contains_traversal?("%252e%252e/etc/passwd")
      assert PathValidator.contains_traversal?("file\x00.txt")
      assert PathValidator.contains_traversal?("\\\\.\\\\../windows/system32")

      refute PathValidator.contains_traversal?("/normal/path/file.txt")
      refute PathValidator.contains_traversal?("file.txt")
      refute PathValidator.contains_traversal?("./current/dir/file.txt")
    end
  end

  describe "has_dangerous_characters?/1" do
    test "detects dangerous characters" do
      assert PathValidator.has_dangerous_characters?("file\x00.txt")
      assert PathValidator.has_dangerous_characters?("file|command")
      assert PathValidator.has_dangerous_characters?("file;command")
      assert PathValidator.has_dangerous_characters?("file&command")
      assert PathValidator.has_dangerous_characters?("file$variable")
      assert PathValidator.has_dangerous_characters?("file`command`")
      assert PathValidator.has_dangerous_characters?("file\ncommand")
      assert PathValidator.has_dangerous_characters?("file\rcommand")

      refute PathValidator.has_dangerous_characters?("normal_file.txt")
      refute PathValidator.has_dangerous_characters?("file-with-dash.txt")
      refute PathValidator.has_dangerous_characters?("file.with.dots.txt")
      refute PathValidator.has_dangerous_characters?("/path/to/file.txt")
    end
  end

  describe "normalize_path/1" do
    test "normalizes paths correctly" do
      assert "path/to/file.txt" = PathValidator.normalize_path("path/to/file.txt")
      assert "path/to/file.txt" = PathValidator.normalize_path("path/./to/file.txt")
      assert "path/to/file.txt" = PathValidator.normalize_path("path/to/./file.txt")
      assert "path/file.txt" = PathValidator.normalize_path("path/to/../file.txt")
      assert "file.txt" = PathValidator.normalize_path("path/../file.txt")
      assert "file.txt" = PathValidator.normalize_path("./file.txt")
      assert "/" = PathValidator.normalize_path("/")
      assert "/" = PathValidator.normalize_path("/..")
      assert "/" = PathValidator.normalize_path("/../..")
    end
  end
end
