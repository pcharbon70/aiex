package filesystem

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"aiex-tui/internal/events"
	"aiex-tui/internal/rpc"
	"aiex-tui/pkg/types"
)

// FileSystemManager handles file operations and integrates with the Elixir backend
type FileSystemManager struct {
	// Core components
	rpcClient    *rpc.Client
	eventStream  *events.EventStreamManager
	stateManager *events.DistributedStateManager
	watcher      *FileWatcher
	cache        *FileCache
	
	// Configuration
	config       FileSystemConfig
	
	// State
	rootPath     string
	workspaces   map[string]*Workspace
	openFiles    map[string]*OpenFile
	fileTree     *FileTree
	
	// Security and validation
	validator    *PathValidator
	permissions  *PermissionManager
	
	// Synchronization
	mutex        sync.RWMutex
	running      bool
	
	// Context
	ctx          context.Context
	cancel       context.CancelFunc
}

// FileSystemConfig configures the file system manager
type FileSystemConfig struct {
	RootPath              string        `json:"root_path"`
	EnableFileWatching    bool          `json:"enable_file_watching"`
	EnableCaching         bool          `json:"enable_caching"`
	CacheSize             int           `json:"cache_size"`
	WatcherDebounceDelay  time.Duration `json:"watcher_debounce_delay"`
	MaxFileSize           int64         `json:"max_file_size"`
	AllowedExtensions     []string      `json:"allowed_extensions"`
	IgnorePatterns        []string      `json:"ignore_patterns"`
	EnableSecurityCheck   bool          `json:"enable_security_check"`
	EnableBackup          bool          `json:"enable_backup"`
	BackupInterval        time.Duration `json:"backup_interval"`
}

// Workspace represents a project workspace
type Workspace struct {
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Path        string                 `json:"path"`
	Type        string                 `json:"type"` // git, local, remote
	Config      map[string]interface{} `json:"config"`
	LastAccessed time.Time             `json:"last_accessed"`
	FileTree    *FileTree             `json:"file_tree"`
	GitInfo     *GitInfo              `json:"git_info,omitempty"`
}

// OpenFile represents an open file with its content and metadata
type OpenFile struct {
	Path         string                 `json:"path"`
	Content      []string               `json:"content"`
	Language     string                 `json:"language"`
	Encoding     string                 `json:"encoding"`
	Modified     bool                   `json:"modified"`
	LastSaved    time.Time              `json:"last_saved"`
	LastAccessed time.Time              `json:"last_accessed"`
	Checksum     string                 `json:"checksum"`
	Metadata     map[string]interface{} `json:"metadata"`
	Collaborators []string              `json:"collaborators,omitempty"`
}

// FileTree represents the hierarchical file structure
type FileTree struct {
	Root     *FileNode          `json:"root"`
	Nodes    map[string]*FileNode `json:"nodes"` // Path -> Node mapping
	Version  int64              `json:"version"`
	Updated  time.Time          `json:"updated"`
}

// FileNode represents a node in the file tree
type FileNode struct {
	Path         string                 `json:"path"`
	Name         string                 `json:"name"`
	Type         string                 `json:"type"` // file, directory
	Size         int64                  `json:"size"`
	ModTime      time.Time              `json:"mod_time"`
	Permissions  string                 `json:"permissions"`
	Children     []*FileNode            `json:"children,omitempty"`
	Parent       *FileNode              `json:"-"` // Avoid circular reference in JSON
	Metadata     map[string]interface{} `json:"metadata"`
	IsExpanded   bool                   `json:"is_expanded"`
	IsLoaded     bool                   `json:"is_loaded"`
	IsWatched    bool                   `json:"is_watched"`
	Language     string                 `json:"language,omitempty"`
	Icon         string                 `json:"icon,omitempty"`
}

// GitInfo represents Git repository information
type GitInfo struct {
	Branch       string            `json:"branch"`
	RemoteURL    string            `json:"remote_url"`
	LastCommit   string            `json:"last_commit"`
	Status       map[string]string `json:"status"` // file -> status
	Staged       []string          `json:"staged"`
	Modified     []string          `json:"modified"`
	Untracked    []string          `json:"untracked"`
}

// FileOperation represents a file system operation
type FileOperation struct {
	ID        string                 `json:"id"`
	Type      string                 `json:"type"` // create, read, update, delete, rename, move
	Path      string                 `json:"path"`
	NewPath   string                 `json:"new_path,omitempty"`
	Content   interface{}            `json:"content,omitempty"`
	Options   map[string]interface{} `json:"options,omitempty"`
	Timestamp time.Time              `json:"timestamp"`
	UserID    string                 `json:"user_id,omitempty"`
	Status    string                 `json:"status"` // pending, success, error
	Error     string                 `json:"error,omitempty"`
}

// NewFileSystemManager creates a new file system manager
func NewFileSystemManager(config FileSystemConfig, rpcClient *rpc.Client, eventStream *events.EventStreamManager) *FileSystemManager {
	ctx, cancel := context.WithCancel(context.Background())
	
	// Set defaults
	if config.CacheSize == 0 {
		config.CacheSize = 100
	}
	if config.WatcherDebounceDelay == 0 {
		config.WatcherDebounceDelay = 100 * time.Millisecond
	}
	if config.MaxFileSize == 0 {
		config.MaxFileSize = 10 * 1024 * 1024 // 10MB
	}
	if config.BackupInterval == 0 {
		config.BackupInterval = 5 * time.Minute
	}
	
	fsm := &FileSystemManager{
		rpcClient:   rpcClient,
		eventStream: eventStream,
		config:      config,
		rootPath:    config.RootPath,
		workspaces:  make(map[string]*Workspace),
		openFiles:   make(map[string]*OpenFile),
		fileTree:    NewFileTree(),
		validator:   NewPathValidator(config),
		permissions: NewPermissionManager(),
		ctx:         ctx,
		cancel:      cancel,
	}
	
	if config.EnableCaching {
		fsm.cache = NewFileCache(config.CacheSize)
	}
	
	if config.EnableFileWatching {
		fsm.watcher = NewFileWatcher(fsm, config.WatcherDebounceDelay)
	}
	
	return fsm
}

// Start begins file system operations
func (fsm *FileSystemManager) Start() error {
	fsm.mutex.Lock()
	defer fsm.mutex.Unlock()
	
	if fsm.running {
		return fmt.Errorf("file system manager already running")
	}
	
	fsm.running = true
	
	// Initialize file tree
	if err := fsm.loadFileTree(); err != nil {
		return fmt.Errorf("failed to load file tree: %w", err)
	}
	
	// Start file watcher
	if fsm.watcher != nil {
		if err := fsm.watcher.Start(); err != nil {
			return fmt.Errorf("failed to start file watcher: %w", err)
		}
	}
	
	// Start backup routine
	if fsm.config.EnableBackup {
		go fsm.backupLoop()
	}
	
	return nil
}

// Stop halts file system operations
func (fsm *FileSystemManager) Stop() error {
	fsm.mutex.Lock()
	defer fsm.mutex.Unlock()
	
	if !fsm.running {
		return fmt.Errorf("file system manager not running")
	}
	
	fsm.running = false
	fsm.cancel()
	
	// Stop file watcher
	if fsm.watcher != nil {
		fsm.watcher.Stop()
	}
	
	// Save any pending changes
	fsm.saveOpenFiles()
	
	return nil
}

// File Operations
func (fsm *FileSystemManager) CreateFile(path, content string) error {
	return fsm.executeFileOperation(FileOperation{
		ID:        fsm.generateOperationID(),
		Type:      "create",
		Path:      path,
		Content:   content,
		Timestamp: time.Now(),
	})
}

func (fsm *FileSystemManager) ReadFile(path string) ([]string, error) {
	// Check cache first
	if fsm.cache != nil {
		if content, found := fsm.cache.Get(path); found {
			return content, nil
		}
	}
	
	// Execute read operation
	op := FileOperation{
		ID:        fsm.generateOperationID(),
		Type:      "read",
		Path:      path,
		Timestamp: time.Now(),
	}
	
	if err := fsm.executeFileOperation(op); err != nil {
		return nil, err
	}
	
	// Get content from open files or cache
	if openFile, exists := fsm.openFiles[path]; exists {
		return openFile.Content, nil
	}
	
	return nil, fmt.Errorf("file content not available")
}

func (fsm *FileSystemManager) UpdateFile(path string, content []string) error {
	return fsm.executeFileOperation(FileOperation{
		ID:        fsm.generateOperationID(),
		Type:      "update",
		Path:      path,
		Content:   content,
		Timestamp: time.Now(),
	})
}

func (fsm *FileSystemManager) DeleteFile(path string) error {
	return fsm.executeFileOperation(FileOperation{
		ID:        fsm.generateOperationID(),
		Type:      "delete",
		Path:      path,
		Timestamp: time.Now(),
	})
}

func (fsm *FileSystemManager) RenameFile(oldPath, newPath string) error {
	return fsm.executeFileOperation(FileOperation{
		ID:        fsm.generateOperationID(),
		Type:      "rename",
		Path:      oldPath,
		NewPath:   newPath,
		Timestamp: time.Now(),
	})
}

func (fsm *FileSystemManager) CreateDirectory(path string) error {
	return fsm.executeFileOperation(FileOperation{
		ID:        fsm.generateOperationID(),
		Type:      "create_dir",
		Path:      path,
		Timestamp: time.Now(),
	})
}

// File Tree Operations
func (fsm *FileSystemManager) GetFileTree() *FileTree {
	fsm.mutex.RLock()
	defer fsm.mutex.RUnlock()
	return fsm.fileTree
}

func (fsm *FileSystemManager) RefreshFileTree() error {
	return fsm.loadFileTree()
}

func (fsm *FileSystemManager) ExpandNode(path string) error {
	fsm.mutex.Lock()
	defer fsm.mutex.Unlock()
	
	node := fsm.fileTree.Nodes[path]
	if node == nil {
		return fmt.Errorf("node not found: %s", path)
	}
	
	if node.Type == "directory" && !node.IsLoaded {
		if err := fsm.loadNodeChildren(node); err != nil {
			return err
		}
	}
	
	node.IsExpanded = true
	return nil
}

func (fsm *FileSystemManager) CollapseNode(path string) error {
	fsm.mutex.Lock()
	defer fsm.mutex.Unlock()
	
	node := fsm.fileTree.Nodes[path]
	if node == nil {
		return fmt.Errorf("node not found: %s", path)
	}
	
	node.IsExpanded = false
	return nil
}

// File Content Management
func (fsm *FileSystemManager) OpenFile(path string) (*OpenFile, error) {
	fsm.mutex.Lock()
	defer fsm.mutex.Unlock()
	
	// Check if already open
	if openFile, exists := fsm.openFiles[path]; exists {
		openFile.LastAccessed = time.Now()
		return openFile, nil
	}
	
	// Validate path
	if err := fsm.validator.ValidatePath(path); err != nil {
		return nil, fmt.Errorf("invalid path: %w", err)
	}
	
	// Check permissions
	if !fsm.permissions.CanRead(path) {
		return nil, fmt.Errorf("permission denied: %s", path)
	}
	
	// Read file content
	content, err := fsm.ReadFile(path)
	if err != nil {
		return nil, err
	}
	
	// Create open file
	openFile := &OpenFile{
		Path:         path,
		Content:      content,
		Language:     fsm.detectLanguage(path),
		Encoding:     "utf-8",
		Modified:     false,
		LastSaved:    time.Now(),
		LastAccessed: time.Now(),
		Checksum:     fsm.calculateChecksum(content),
		Metadata:     make(map[string]interface{}),
	}
	
	fsm.openFiles[path] = openFile
	
	// Send event
	fsm.sendFileEvent("file_opened", path, map[string]interface{}{
		"language": openFile.Language,
		"size":     len(content),
	})
	
	return openFile, nil
}

func (fsm *FileSystemManager) CloseFile(path string) error {
	fsm.mutex.Lock()
	defer fsm.mutex.Unlock()
	
	openFile, exists := fsm.openFiles[path]
	if !exists {
		return fmt.Errorf("file not open: %s", path)
	}
	
	// Save if modified
	if openFile.Modified {
		if err := fsm.SaveFile(path); err != nil {
			return fmt.Errorf("failed to save file before closing: %w", err)
		}
	}
	
	delete(fsm.openFiles, path)
	
	// Send event
	fsm.sendFileEvent("file_closed", path, nil)
	
	return nil
}

func (fsm *FileSystemManager) SaveFile(path string) error {
	fsm.mutex.Lock()
	defer fsm.mutex.Unlock()
	
	openFile, exists := fsm.openFiles[path]
	if !exists {
		return fmt.Errorf("file not open: %s", path)
	}
	
	if !openFile.Modified {
		return nil // No changes to save
	}
	
	// Check permissions
	if !fsm.permissions.CanWrite(path) {
		return fmt.Errorf("permission denied: %s", path)
	}
	
	// Save content
	if err := fsm.UpdateFile(path, openFile.Content); err != nil {
		return err
	}
	
	// Update metadata
	openFile.Modified = false
	openFile.LastSaved = time.Now()
	openFile.Checksum = fsm.calculateChecksum(openFile.Content)
	
	// Update cache
	if fsm.cache != nil {
		fsm.cache.Set(path, openFile.Content)
	}
	
	// Send event
	fsm.sendFileEvent("file_saved", path, map[string]interface{}{
		"size": len(openFile.Content),
	})
	
	return nil
}

func (fsm *FileSystemManager) GetOpenFile(path string) (*OpenFile, bool) {
	fsm.mutex.RLock()
	defer fsm.mutex.RUnlock()
	
	openFile, exists := fsm.openFiles[path]
	return openFile, exists
}

func (fsm *FileSystemManager) GetOpenFiles() map[string]*OpenFile {
	fsm.mutex.RLock()
	defer fsm.mutex.RUnlock()
	
	// Return a copy
	result := make(map[string]*OpenFile)
	for path, file := range fsm.openFiles {
		result[path] = file
	}
	return result
}

func (fsm *FileSystemManager) ModifyFileContent(path string, content []string) error {
	fsm.mutex.Lock()
	defer fsm.mutex.Unlock()
	
	openFile, exists := fsm.openFiles[path]
	if !exists {
		return fmt.Errorf("file not open: %s", path)
	}
	
	// Check permissions
	if !fsm.permissions.CanWrite(path) {
		return fmt.Errorf("permission denied: %s", path)
	}
	
	openFile.Content = content
	openFile.Modified = true
	openFile.LastAccessed = time.Now()
	
	// Send event
	fsm.sendFileEvent("file_content_modified", path, map[string]interface{}{
		"size": len(content),
	})
	
	return nil
}

// Workspace Management
func (fsm *FileSystemManager) CreateWorkspace(name, path string) (*Workspace, error) {
	workspace := &Workspace{
		ID:           fsm.generateWorkspaceID(),
		Name:         name,
		Path:         path,
		Type:         "local",
		Config:       make(map[string]interface{}),
		LastAccessed: time.Now(),
		FileTree:     NewFileTree(),
	}
	
	// Check if it's a Git repository
	if gitInfo, err := fsm.loadGitInfo(path); err == nil {
		workspace.GitInfo = gitInfo
		workspace.Type = "git"
	}
	
	fsm.workspaces[workspace.ID] = workspace
	
	return workspace, nil
}

func (fsm *FileSystemManager) GetWorkspace(id string) (*Workspace, bool) {
	fsm.mutex.RLock()
	defer fsm.mutex.RUnlock()
	
	workspace, exists := fsm.workspaces[id]
	return workspace, exists
}

func (fsm *FileSystemManager) GetWorkspaces() map[string]*Workspace {
	fsm.mutex.RLock()
	defer fsm.mutex.RUnlock()
	
	result := make(map[string]*Workspace)
	for id, workspace := range fsm.workspaces {
		result[id] = workspace
	}
	return result
}

// Internal methods
func (fsm *FileSystemManager) executeFileOperation(op FileOperation) error {
	// Validate operation
	if err := fsm.validator.ValidateOperation(op); err != nil {
		return fmt.Errorf("operation validation failed: %w", err)
	}
	
	// Send to Elixir backend via RPC
	ctx, cancel := context.WithTimeout(fsm.ctx, 10*time.Second)
	defer cancel()
	
	response, err := fsm.rpcClient.Call(ctx, "filesystem.execute_operation", op)
	if err != nil {
		return fmt.Errorf("RPC call failed: %w", err)
	}
	
	// Process response
	var result map[string]interface{}
	if err := json.Unmarshal(response, &result); err != nil {
		return fmt.Errorf("failed to parse response: %w", err)
	}
	
	if status, ok := result["status"].(string); ok && status == "error" {
		if errorMsg, ok := result["error"].(string); ok {
			return fmt.Errorf("operation failed: %s", errorMsg)
		}
		return fmt.Errorf("operation failed")
	}
	
	// Update local state based on operation
	fsm.updateLocalState(op, result)
	
	return nil
}

func (fsm *FileSystemManager) updateLocalState(op FileOperation, result map[string]interface{}) {
	switch op.Type {
	case "read":
		if content, ok := result["content"].([]interface{}); ok {
			lines := make([]string, len(content))
			for i, line := range content {
				if str, ok := line.(string); ok {
					lines[i] = str
				}
			}
			
			// Update cache
			if fsm.cache != nil {
				fsm.cache.Set(op.Path, lines)
			}
			
			// Update open file if exists
			if openFile, exists := fsm.openFiles[op.Path]; exists {
				openFile.Content = lines
				openFile.LastAccessed = time.Now()
			}
		}
		
	case "create", "update":
		// Invalidate cache
		if fsm.cache != nil {
			fsm.cache.Invalidate(op.Path)
		}
		
		// Update file tree
		fsm.updateFileTreeNode(op.Path)
		
	case "delete":
		// Remove from cache
		if fsm.cache != nil {
			fsm.cache.Invalidate(op.Path)
		}
		
		// Remove from open files
		delete(fsm.openFiles, op.Path)
		
		// Update file tree
		fsm.removeFileTreeNode(op.Path)
		
	case "rename":
		// Update cache
		if fsm.cache != nil {
			if content, found := fsm.cache.Get(op.Path); found {
				fsm.cache.Set(op.NewPath, content)
				fsm.cache.Invalidate(op.Path)
			}
		}
		
		// Update open files
		if openFile, exists := fsm.openFiles[op.Path]; exists {
			openFile.Path = op.NewPath
			fsm.openFiles[op.NewPath] = openFile
			delete(fsm.openFiles, op.Path)
		}
		
		// Update file tree
		fsm.renameFileTreeNode(op.Path, op.NewPath)
	}
}

func (fsm *FileSystemManager) loadFileTree() error {
	// This would make an RPC call to get the file tree from Elixir
	ctx, cancel := context.WithTimeout(fsm.ctx, 10*time.Second)
	defer cancel()
	
	response, err := fsm.rpcClient.Call(ctx, "filesystem.get_file_tree", map[string]interface{}{
		"path": fsm.rootPath,
	})
	if err != nil {
		return err
	}
	
	// Parse response and build file tree
	// Implementation would parse the JSON response
	
	return nil
}

func (fsm *FileSystemManager) loadNodeChildren(node *FileNode) error {
	// Load children for a directory node
	ctx, cancel := context.WithTimeout(fsm.ctx, 5*time.Second)
	defer cancel()
	
	response, err := fsm.rpcClient.Call(ctx, "filesystem.get_directory_contents", map[string]interface{}{
		"path": node.Path,
	})
	if err != nil {
		return err
	}
	
	// Parse response and add children
	// Implementation would parse the JSON response
	
	node.IsLoaded = true
	return nil
}

func (fsm *FileSystemManager) detectLanguage(path string) string {
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".go":
		return "go"
	case ".ex", ".exs":
		return "elixir"
	case ".js":
		return "javascript"
	case ".ts":
		return "typescript"
	case ".py":
		return "python"
	case ".rs":
		return "rust"
	case ".md":
		return "markdown"
	case ".json":
		return "json"
	case ".yml", ".yaml":
		return "yaml"
	case ".toml":
		return "toml"
	default:
		return "text"
	}
}

func (fsm *FileSystemManager) calculateChecksum(content []string) string {
	// Simple checksum implementation
	var total int
	for _, line := range content {
		for _, char := range line {
			total += int(char)
		}
	}
	return fmt.Sprintf("%x", total)
}

func (fsm *FileSystemManager) sendFileEvent(eventType, path string, metadata map[string]interface{}) {
	if fsm.eventStream == nil {
		return
	}
	
	if metadata == nil {
		metadata = make(map[string]interface{})
	}
	metadata["path"] = path
	
	event := events.StreamEvent{
		ID:       fmt.Sprintf("file_%d", time.Now().UnixNano()),
		Type:     eventType,
		Category: events.CategoryFileSystem,
		Priority: events.PriorityNormal,
		Payload:  metadata,
		Metadata: metadata,
		Timestamp: time.Now(),
		Source:   "filesystem_manager",
	}
	
	fsm.eventStream.ProcessEvent(event)
}

func (fsm *FileSystemManager) generateOperationID() string {
	return fmt.Sprintf("op_%d", time.Now().UnixNano())
}

func (fsm *FileSystemManager) generateWorkspaceID() string {
	return fmt.Sprintf("ws_%d", time.Now().UnixNano())
}

func (fsm *FileSystemManager) saveOpenFiles() {
	for _, openFile := range fsm.openFiles {
		if openFile.Modified {
			fsm.SaveFile(openFile.Path)
		}
	}
}

func (fsm *FileSystemManager) backupLoop() {
	ticker := time.NewTicker(fsm.config.BackupInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-fsm.ctx.Done():
			return
		case <-ticker.C:
			fsm.performBackup()
		}
	}
}

func (fsm *FileSystemManager) performBackup() {
	// Implementation for backup operations
}

func (fsm *FileSystemManager) updateFileTreeNode(path string) {
	// Implementation for updating file tree nodes
}

func (fsm *FileSystemManager) removeFileTreeNode(path string) {
	// Implementation for removing file tree nodes
}

func (fsm *FileSystemManager) renameFileTreeNode(oldPath, newPath string) {
	// Implementation for renaming file tree nodes
}

func (fsm *FileSystemManager) loadGitInfo(path string) (*GitInfo, error) {
	// Implementation for loading Git information
	return nil, fmt.Errorf("not a git repository")
}

// Factory functions
func NewFileTree() *FileTree {
	return &FileTree{
		Nodes:   make(map[string]*FileNode),
		Version: 0,
		Updated: time.Now(),
	}
}

// Placeholder implementations for supporting types
type FileWatcher struct{}
func NewFileWatcher(fsm *FileSystemManager, debounce time.Duration) *FileWatcher { return &FileWatcher{} }
func (fw *FileWatcher) Start() error { return nil }
func (fw *FileWatcher) Stop() error { return nil }

type FileCache struct{}
func NewFileCache(size int) *FileCache { return &FileCache{} }
func (fc *FileCache) Get(path string) ([]string, bool) { return nil, false }
func (fc *FileCache) Set(path string, content []string) {}
func (fc *FileCache) Invalidate(path string) {}

type PathValidator struct{}
func NewPathValidator(config FileSystemConfig) *PathValidator { return &PathValidator{} }
func (pv *PathValidator) ValidatePath(path string) error { return nil }
func (pv *PathValidator) ValidateOperation(op FileOperation) error { return nil }

type PermissionManager struct{}
func NewPermissionManager() *PermissionManager { return &PermissionManager{} }
func (pm *PermissionManager) CanRead(path string) bool { return true }
func (pm *PermissionManager) CanWrite(path string) bool { return true }