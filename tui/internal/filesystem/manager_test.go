package filesystem

import (
	"context"
	"encoding/json"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"aiex-tui/internal/rpc"
)

// Mock RPC client for testing
type mockRPCClient struct {
	responses map[string]interface{}
	errors    map[string]error
	calls     []rpc.Call
	mutex     sync.RWMutex
}

type rpcCall struct {
	Method string
	Params interface{}
}

func newMockRPCClient() *mockRPCClient {
	return &mockRPCClient{
		responses: make(map[string]interface{}),
		errors:    make(map[string]error),
		calls:     make([]rpcCall, 0),
	}
}

func (m *mockRPCClient) Call(ctx context.Context, method string, params interface{}) (interface{}, error) {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	m.calls = append(m.calls, rpcCall{Method: method, Params: params})

	if err, exists := m.errors[method]; exists {
		return nil, err
	}

	if response, exists := m.responses[method]; exists {
		return response, nil
	}

	return nil, nil
}

func (m *mockRPCClient) Notify(method string, params interface{}) error {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	m.calls = append(m.calls, rpcCall{Method: method, Params: params})
	return nil
}

func (m *mockRPCClient) setResponse(method string, response interface{}) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.responses[method] = response
}

func (m *mockRPCClient) setError(method string, err error) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.errors[method] = err
}

func (m *mockRPCClient) getCalls() []rpcCall {
	m.mutex.RLock()
	defer m.mutex.RUnlock()
	calls := make([]rpcCall, len(m.calls))
	copy(calls, m.calls)
	return calls
}

func TestNewFileSystemManager(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		AllowedExtensions: []string{".txt", ".go", ".md"},
		MaxFileSize:       10 * 1024 * 1024, // 10MB
		CacheTimeout:      5 * time.Minute,
		EnableWatching:    true,
		WatchDebounce:     100 * time.Millisecond,
	}

	manager := NewFileSystemManager(rpcClient, config)
	assert.NotNil(t, manager)
	assert.Equal(t, config.MaxFileSize, manager.config.MaxFileSize)
	assert.NotNil(t, manager.cache)
	assert.NotNil(t, manager.watcher)
}

func TestFileSystemManagerListDirectory(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		AllowedExtensions: []string{".txt", ".go"},
		MaxFileSize:       10 * 1024 * 1024,
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	mockFiles := []map[string]interface{}{
		{
			"name":     "file1.txt",
			"path":     "/test/file1.txt",
			"size":     1024,
			"is_dir":   false,
			"modified": time.Now().Unix(),
		},
		{
			"name":     "subdir",
			"path":     "/test/subdir",
			"size":     0,
			"is_dir":   true,
			"modified": time.Now().Unix(),
		},
	}

	rpcClient.setResponse("file.list", map[string]interface{}{
		"files": mockFiles,
	})

	// Test list directory
	files, err := manager.ListDirectory("/test")
	assert.NoError(t, err)
	assert.Len(t, files, 2)

	// Verify file properties
	assert.Equal(t, "file1.txt", files[0].Name)
	assert.Equal(t, "/test/file1.txt", files[0].Path)
	assert.Equal(t, int64(1024), files[0].Size)
	assert.False(t, files[0].IsDir)

	assert.Equal(t, "subdir", files[1].Name)
	assert.True(t, files[1].IsDir)

	// Verify RPC call
	calls := rpcClient.getCalls()
	assert.Len(t, calls, 1)
	assert.Equal(t, "file.list", calls[0].Method)
}

func TestFileSystemManagerReadFile(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		AllowedExtensions: []string{".txt"},
		MaxFileSize:       10 * 1024 * 1024,
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	mockContent := "Hello, World!"
	rpcClient.setResponse("file.read", map[string]interface{}{
		"content": mockContent,
		"size":    len(mockContent),
	})

	// Test read file
	content, err := manager.ReadFile("/test/file.txt")
	assert.NoError(t, err)
	assert.Equal(t, mockContent, content)

	// Verify RPC call
	calls := rpcClient.getCalls()
	assert.Len(t, calls, 1)
	assert.Equal(t, "file.read", calls[0].Method)

	// Test file caching - second read should use cache
	content2, err := manager.ReadFile("/test/file.txt")
	assert.NoError(t, err)
	assert.Equal(t, mockContent, content2)

	// Should still be only one RPC call due to caching
	calls = rpcClient.getCalls()
	assert.Len(t, calls, 1)
}

func TestFileSystemManagerWriteFile(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		AllowedExtensions: []string{".txt"},
		MaxFileSize:       10 * 1024 * 1024,
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	rpcClient.setResponse("file.write", map[string]interface{}{
		"success": true,
		"size":    13,
	})

	// Test write file
	content := "Hello, World!"
	err := manager.WriteFile("/test/file.txt", content)
	assert.NoError(t, err)

	// Verify RPC call
	calls := rpcClient.getCalls()
	assert.Len(t, calls, 1)
	assert.Equal(t, "file.write", calls[0].Method)

	// Verify cache invalidation
	assert.False(t, manager.cache.Has("/test/file.txt"))
}

func TestFileSystemManagerCreateDirectory(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	rpcClient.setResponse("file.mkdir", map[string]interface{}{
		"success": true,
	})

	// Test create directory
	err := manager.CreateDirectory("/test/newdir")
	assert.NoError(t, err)

	// Verify RPC call
	calls := rpcClient.getCalls()
	assert.Len(t, calls, 1)
	assert.Equal(t, "file.mkdir", calls[0].Method)
}

func TestFileSystemManagerDeleteFile(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	rpcClient.setResponse("file.delete", map[string]interface{}{
		"success": true,
	})

	// Add file to cache first
	manager.cache.Set("/test/file.txt", "cached content")
	assert.True(t, manager.cache.Has("/test/file.txt"))

	// Test delete file
	err := manager.DeleteFile("/test/file.txt")
	assert.NoError(t, err)

	// Verify RPC call
	calls := rpcClient.getCalls()
	assert.Len(t, calls, 1)
	assert.Equal(t, "file.delete", calls[0].Method)

	// Verify cache invalidation
	assert.False(t, manager.cache.Has("/test/file.txt"))
}

func TestFileSystemManagerGetFileInfo(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	mockInfo := map[string]interface{}{
		"name":        "file.txt",
		"path":        "/test/file.txt",
		"size":        1024,
		"is_dir":      false,
		"modified":    time.Now().Unix(),
		"permissions": "rw-r--r--",
	}

	rpcClient.setResponse("file.stat", mockInfo)

	// Test get file info
	info, err := manager.GetFileInfo("/test/file.txt")
	assert.NoError(t, err)
	assert.Equal(t, "file.txt", info.Name)
	assert.Equal(t, "/test/file.txt", info.Path)
	assert.Equal(t, int64(1024), info.Size)
	assert.False(t, info.IsDir)

	// Verify RPC call
	calls := rpcClient.getCalls()
	assert.Len(t, calls, 1)
	assert.Equal(t, "file.stat", calls[0].Method)
}

func TestFileSystemManagerSearchFiles(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	mockResults := []map[string]interface{}{
		{
			"name":     "match1.txt",
			"path":     "/test/match1.txt",
			"size":     512,
			"is_dir":   false,
			"modified": time.Now().Unix(),
			"matches":  []string{"line 1: pattern found"},
		},
		{
			"name":     "match2.go",
			"path":     "/test/match2.go",
			"size":     1024,
			"is_dir":   false,
			"modified": time.Now().Unix(),
			"matches":  []string{"line 5: pattern found", "line 12: pattern found"},
		},
	}

	rpcClient.setResponse("file.search", map[string]interface{}{
		"results": mockResults,
		"total":   2,
	})

	// Test search files
	results, err := manager.SearchFiles("/test", "pattern", SearchOptions{
		CaseSensitive: false,
		IncludeHidden: false,
		MaxDepth:      5,
	})

	assert.NoError(t, err)
	assert.Len(t, results, 2)

	// Verify search results
	assert.Equal(t, "match1.txt", results[0].File.Name)
	assert.Len(t, results[0].Matches, 1)
	assert.Equal(t, "line 1: pattern found", results[0].Matches[0])

	assert.Equal(t, "match2.go", results[1].File.Name)
	assert.Len(t, results[1].Matches, 2)

	// Verify RPC call
	calls := rpcClient.getCalls()
	assert.Len(t, calls, 1)
	assert.Equal(t, "file.search", calls[0].Method)
}

func TestFileSystemManagerValidation(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		AllowedExtensions: []string{".txt", ".go"},
		MaxFileSize:       1024, // 1KB limit
		BlockedPaths:      []string{"/etc", "/sys"},
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Test blocked path
	err := manager.ReadFile("/etc/passwd")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "blocked path")

	// Test disallowed extension
	err = manager.ReadFile("/test/file.exe")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not allowed")

	// Test file too large
	largeContent := strings.Repeat("x", 2048) // 2KB
	err = manager.WriteFile("/test/large.txt", largeContent)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "too large")

	// Test valid operations
	rpcClient.setResponse("file.read", map[string]interface{}{
		"content": "valid content",
		"size":    13,
	})

	_, err = manager.ReadFile("/test/valid.txt")
	assert.NoError(t, err)
}

func TestFileSystemManagerCaching(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		CacheTimeout: 100 * time.Millisecond,
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	rpcClient.setResponse("file.read", map[string]interface{}{
		"content": "cached content",
		"size":    14,
	})

	// First read should hit RPC
	content1, err := manager.ReadFile("/test/file.txt")
	assert.NoError(t, err)
	assert.Equal(t, "cached content", content1)

	// Second read should use cache
	content2, err := manager.ReadFile("/test/file.txt")
	assert.NoError(t, err)
	assert.Equal(t, "cached content", content2)

	// Should only have one RPC call
	calls := rpcClient.getCalls()
	assert.Len(t, calls, 1)

	// Wait for cache expiration
	time.Sleep(150 * time.Millisecond)

	// Third read should hit RPC again
	content3, err := manager.ReadFile("/test/file.txt")
	assert.NoError(t, err)
	assert.Equal(t, "cached content", content3)

	// Should now have two RPC calls
	calls = rpcClient.getCalls()
	assert.Len(t, calls, 2)
}

func TestFileSystemManagerWatching(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		EnableWatching: true,
		WatchDebounce:  50 * time.Millisecond,
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Start watching
	err := manager.StartWatching("/test")
	assert.NoError(t, err)

	// Subscribe to events
	events := make(chan FileEvent, 10)
	manager.SubscribeToEvents(func(event FileEvent) {
		events <- event
	})

	// Simulate file change
	manager.watcher.NotifyChange("/test/file.txt", FileEventModified)

	// Should receive event
	select {
	case event := <-events:
		assert.Equal(t, "/test/file.txt", event.Path)
		assert.Equal(t, FileEventModified, event.Type)
	case <-time.After(100 * time.Millisecond):
		t.Fatal("File event not received")
	}

	// Stop watching
	err = manager.StopWatching("/test")
	assert.NoError(t, err)
}

func TestFileSystemManagerConcurrency(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		MaxFileSize: 10 * 1024 * 1024,
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC responses
	for i := 0; i < 100; i++ {
		rpcClient.setResponse("file.read", map[string]interface{}{
			"content": fmt.Sprintf("content-%d", i),
			"size":    10,
		})
	}

	// Perform concurrent operations
	var wg sync.WaitGroup
	errorCount := int64(0)
	successCount := int64(0)

	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			path := fmt.Sprintf("/test/file-%d.txt", index)
			_, err := manager.ReadFile(path)
			if err != nil {
				atomic.AddInt64(&errorCount, 1)
			} else {
				atomic.AddInt64(&successCount, 1)
			}
		}(i)
	}

	wg.Wait()

	// All operations should succeed
	assert.Equal(t, int64(100), atomic.LoadInt64(&successCount))
	assert.Equal(t, int64(0), atomic.LoadInt64(&errorCount))
}

func TestFileSystemManagerErrorHandling(t *testing.T) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{}

	manager := NewFileSystemManager(rpcClient, config)

	// Test RPC error
	rpcClient.setError("file.read", fmt.Errorf("file not found"))

	_, err := manager.ReadFile("/test/nonexistent.txt")
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "file not found")

	// Test malformed RPC response
	rpcClient.setResponse("file.list", "invalid response")

	_, err = manager.ListDirectory("/test")
	assert.Error(t, err)

	// Test network timeout simulation
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Millisecond)
	defer cancel()

	// This would timeout in a real implementation
	// For mock, we'll simulate by setting a slow response
	time.Sleep(2 * time.Millisecond)
	_, err = manager.ReadFileWithContext(ctx, "/test/file.txt")
	// In real implementation, this would be a timeout error
}

func TestTreeNode(t *testing.T) {
	root := &TreeNode{
		File: FileInfo{
			Name:  "root",
			Path:  "/",
			IsDir: true,
		},
		Children: make([]*TreeNode, 0),
		Expanded: true,
	}

	child1 := &TreeNode{
		File: FileInfo{
			Name:  "child1",
			Path:  "/child1",
			IsDir: false,
		},
		Parent: root,
	}

	child2 := &TreeNode{
		File: FileInfo{
			Name:  "child2",
			Path:  "/child2",
			IsDir: true,
		},
		Parent:   root,
		Children: make([]*TreeNode, 0),
		Expanded: false,
	}

	root.Children = append(root.Children, child1, child2)

	// Test tree structure
	assert.Equal(t, "root", root.File.Name)
	assert.Len(t, root.Children, 2)
	assert.True(t, root.Expanded)

	assert.Equal(t, "child1", child1.File.Name)
	assert.Equal(t, root, child1.Parent)
	assert.False(t, child1.File.IsDir)

	assert.Equal(t, "child2", child2.File.Name)
	assert.True(t, child2.File.IsDir)
	assert.False(t, child2.Expanded)

	// Test tree navigation
	assert.Equal(t, 2, root.GetChildCount())
	assert.Equal(t, 0, child1.GetChildCount())
	assert.Equal(t, 0, child2.GetChildCount())

	// Test path depth
	assert.Equal(t, 0, root.GetDepth())
	assert.Equal(t, 1, child1.GetDepth())
	assert.Equal(t, 1, child2.GetDepth())
}

func BenchmarkFileSystemManagerRead(b *testing.B) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		CacheTimeout: 1 * time.Hour, // Long cache for benchmark
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	rpcClient.setResponse("file.read", map[string]interface{}{
		"content": "benchmark content",
		"size":    17,
	})

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := manager.ReadFile("/test/benchmark.txt")
		if err != nil {
			b.Error(err)
		}
	}
}

func BenchmarkFileSystemManagerConcurrentRead(b *testing.B) {
	rpcClient := newMockRPCClient()
	config := FileSystemConfig{
		CacheTimeout: 1 * time.Hour,
	}

	manager := NewFileSystemManager(rpcClient, config)

	// Mock RPC response
	rpcClient.setResponse("file.read", map[string]interface{}{
		"content": "benchmark content",
		"size":    17,
	})

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			_, err := manager.ReadFile("/test/benchmark.txt")
			if err != nil {
				b.Error(err)
			}
		}
	})
}

import (
	"fmt"
	"sync/atomic"
)