package ui

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"aiex-tui/pkg/types"
)

// FileExplorerModel represents an enhanced file explorer with tree navigation
type FileExplorerModel struct {
	width       int
	height      int
	files       []types.FileInfo
	tree        *FileNode
	selected    int
	expanded    map[string]bool
	focused     bool
	viewport    ViewportState
	filter      string
	showHidden  bool
	sortBy      SortCriteria
	rootPath    string
}

// FileNode represents a node in the file tree
type FileNode struct {
	Info     types.FileInfo
	Children []*FileNode
	Parent   *FileNode
	Expanded bool
	Level    int
}

// SortCriteria defines how files should be sorted
type SortCriteria int

const (
	SortByName SortCriteria = iota
	SortByType
	SortBySize
	SortByModified
)

// NewFileExplorerModel creates a new file explorer
func NewFileExplorerModel(rootPath string) FileExplorerModel {
	return FileExplorerModel{
		expanded:   make(map[string]bool),
		showHidden: false,
		sortBy:     SortByName,
		rootPath:   rootPath,
		viewport: ViewportState{
			offset: 0,
			height: 0,
		},
	}
}

// Update handles file explorer updates
func (fem FileExplorerModel) Update(msg tea.Msg) (FileExplorerModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !fem.focused {
			return fem, nil
		}
		
		switch msg.String() {
		case "up", "k":
			return fem.moveCursorUp(), nil
			
		case "down", "j":
			return fem.moveCursorDown(), nil
			
		case "left", "h":
			return fem.collapseOrMoveUp(), nil
			
		case "right", "l":
			return fem.expandOrMoveDown(), nil
			
		case "enter", " ":
			return fem.toggleExpanded(), fem.selectFile()
			
		case "o":
			return fem, fem.openFile()
			
		case "r":
			return fem, fem.refreshFiles()
			
		case "n":
			return fem, fem.createNewFile()
			
		case "d":
			return fem, fem.deleteFile()
			
		case "f":
			return fem.toggleFilter(), nil
			
		case "h":
			fem.showHidden = !fem.showHidden
			return fem, fem.refreshFiles()
			
		case "s":
			fem.sortBy = (fem.sortBy + 1) % 4
			return fem.sortFiles(), nil
			
		case "esc":
			fem.filter = ""
			return fem, nil
		}
		
		// Handle filter input
		if fem.filter != "" && len(msg.Runes) > 0 {
			fem.filter += string(msg.Runes)
			return fem.applyFilter(), nil
		}
		
	case FileTreeUpdatedMsg:
		fem.files = msg.Files
		fem.tree = fem.buildTree(msg.Files)
		return fem.sortFiles(), nil
		
	case FileOperationCompletedMsg:
		return fem, fem.refreshFiles()
	}
	
	return fem, nil
}

// View renders the file explorer
func (fem FileExplorerModel) View() string {
	if fem.width == 0 || fem.height == 0 {
		return ""
	}
	
	style := lipgloss.NewStyle().
		Width(fem.width).
		Height(fem.height).
		Background(lipgloss.Color("237")).
		Foreground(lipgloss.Color("255")).
		Padding(0, 1)
	
	if fem.focused {
		style = style.
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("63"))
	} else {
		style = style.
			BorderStyle(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color("241"))
	}
	
	var content strings.Builder
	
	// Header with title and controls
	title := "📁 Files"
	if fem.filter != "" {
		title += fmt.Sprintf(" (filter: %s)", fem.filter)
	}
	content.WriteString(fem.renderTitle(title))
	content.WriteString("\n")
	content.WriteString(strings.Repeat("─", fem.width-2))
	content.WriteString("\n")
	
	// File tree
	if fem.tree != nil {
		lines := fem.renderTree(fem.tree, 0)
		visibleLines := fem.getVisibleLines(lines)
		
		for i, line := range visibleLines {
			if i+2 >= fem.height-1 { // Account for header and separator
				break
			}
			content.WriteString(line)
			if i < len(visibleLines)-1 {
				content.WriteString("\n")
			}
		}
	}
	
	// Status line
	if fem.height > 3 {
		content.WriteString("\n")
		content.WriteString(fem.renderStatusLine())
	}
	
	return style.Render(content.String())
}

// renderTree recursively renders the file tree
func (fem FileExplorerModel) renderTree(node *FileNode, currentIndex int) []string {
	var lines []string
	
	if node == nil {
		return lines
	}
	
	// Render current node
	if node.Level >= 0 { // Skip root level
		line := fem.renderFileNode(node, currentIndex == fem.selected)
		lines = append(lines, line)
		currentIndex++
	}
	
	// Render children if expanded
	if node.Expanded || node.Level < 0 {
		for _, child := range node.Children {
			childLines := fem.renderTree(child, currentIndex)
			lines = append(lines, childLines...)
			currentIndex += len(childLines)
		}
	}
	
	return lines
}

// renderFileNode renders a single file node
func (fem FileExplorerModel) renderFileNode(node *FileNode, selected bool) string {
	var builder strings.Builder
	
	// Indentation
	indent := strings.Repeat("  ", node.Level)
	builder.WriteString(indent)
	
	// Expansion indicator
	if node.Info.Type == "directory" {
		if len(node.Children) > 0 {
			if node.Expanded {
				builder.WriteString("▼ ")
			} else {
				builder.WriteString("▶ ")
			}
		} else {
			builder.WriteString("  ")
		}
	} else {
		builder.WriteString("  ")
	}
	
	// Icon
	icon := fem.getFileIcon(node.Info)
	builder.WriteString(icon)
	builder.WriteString(" ")
	
	// Name
	name := node.Info.Name
	if selected {
		name = lipgloss.NewStyle().
			Background(lipgloss.Color("63")).
			Foreground(lipgloss.Color("230")).
			Render(name)
	}
	builder.WriteString(name)
	
	// Additional info for files
	if node.Info.Type == "file" && fem.width > 40 {
		sizeStr := fem.formatFileSize(node.Info.Size)
		builder.WriteString(fmt.Sprintf(" (%s)", sizeStr))
	}
	
	return builder.String()
}

// getFileIcon returns an appropriate icon for the file type
func (fem FileExplorerModel) getFileIcon(file types.FileInfo) string {
	if file.Type == "directory" {
		return "📁"
	}
	
	ext := strings.ToLower(filepath.Ext(file.Name))
	switch ext {
	case ".go":
		return "🐹"
	case ".ex", ".exs":
		return "💧"
	case ".js", ".ts":
		return "📜"
	case ".py":
		return "🐍"
	case ".rs":
		return "🦀"
	case ".md":
		return "📝"
	case ".json":
		return "📋"
	case ".yml", ".yaml":
		return "⚙️"
	case ".toml":
		return "🔧"
	case ".txt":
		return "📄"
	case ".git":
		return "🔀"
	default:
		return "📄"
	}
}

// formatFileSize formats file size in human-readable format
func (fem FileExplorerModel) formatFileSize(size int64) string {
	if size < 1024 {
		return fmt.Sprintf("%dB", size)
	}
	if size < 1024*1024 {
		return fmt.Sprintf("%.1fK", float64(size)/1024)
	}
	if size < 1024*1024*1024 {
		return fmt.Sprintf("%.1fM", float64(size)/(1024*1024))
	}
	return fmt.Sprintf("%.1fG", float64(size)/(1024*1024*1024))
}

// buildTree builds a tree structure from file list
func (fem FileExplorerModel) buildTree(files []types.FileInfo) *FileNode {
	root := &FileNode{
		Info: types.FileInfo{
			Name: fem.rootPath,
			Type: "directory",
			Path: fem.rootPath,
		},
		Children: make([]*FileNode, 0),
		Level:    -1,
		Expanded: true,
	}
	
	// Sort files
	sortedFiles := fem.sortFileList(files)
	
	// Build tree recursively
	for _, file := range sortedFiles {
		fem.insertFileIntoTree(root, file, 0)
	}
	
	return root
}

// insertFileIntoTree inserts a file into the appropriate position in the tree
func (fem FileExplorerModel) insertFileIntoTree(parent *FileNode, file types.FileInfo, level int) {
	// Create new node
	node := &FileNode{
		Info:     file,
		Children: make([]*FileNode, 0),
		Parent:   parent,
		Level:    level,
		Expanded: fem.expanded[file.Path],
	}
	
	// Add to parent
	parent.Children = append(parent.Children, node)
	
	// Add children if it's a directory
	if file.Type == "directory" && len(file.Children) > 0 {
		for _, child := range file.Children {
			fem.insertFileIntoTree(node, child, level+1)
		}
	}
}

// sortFileList sorts files according to current criteria
func (fem FileExplorerModel) sortFileList(files []types.FileInfo) []types.FileInfo {
	sorted := make([]types.FileInfo, len(files))
	copy(sorted, files)
	
	sort.Slice(sorted, func(i, j int) bool {
		// Directories first
		if sorted[i].Type != sorted[j].Type {
			return sorted[i].Type == "directory"
		}
		
		switch fem.sortBy {
		case SortByName:
			return sorted[i].Name < sorted[j].Name
		case SortByType:
			return filepath.Ext(sorted[i].Name) < filepath.Ext(sorted[j].Name)
		case SortBySize:
			return sorted[i].Size < sorted[j].Size
		case SortByModified:
			return sorted[i].ModifiedTime.After(sorted[j].ModifiedTime)
		default:
			return sorted[i].Name < sorted[j].Name
		}
	})
	
	return sorted
}

// Navigation methods
func (fem FileExplorerModel) moveCursorUp() FileExplorerModel {
	if fem.selected > 0 {
		fem.selected--
		fem.adjustViewport()
	}
	return fem
}

func (fem FileExplorerModel) moveCursorDown() FileExplorerModel {
	maxIndex := fem.getVisibleFileCount() - 1
	if fem.selected < maxIndex {
		fem.selected++
		fem.adjustViewport()
	}
	return fem
}

func (fem FileExplorerModel) collapseOrMoveUp() FileExplorerModel {
	currentNode := fem.getSelectedNode()
	if currentNode != nil {
		if currentNode.Expanded && currentNode.Info.Type == "directory" {
			// Collapse current directory
			currentNode.Expanded = false
			fem.expanded[currentNode.Info.Path] = false
		} else if currentNode.Parent != nil && currentNode.Parent.Level >= 0 {
			// Move to parent directory
			fem.selected = fem.getNodeIndex(currentNode.Parent)
		}
	}
	return fem
}

func (fem FileExplorerModel) expandOrMoveDown() FileExplorerModel {
	currentNode := fem.getSelectedNode()
	if currentNode != nil && currentNode.Info.Type == "directory" {
		if !currentNode.Expanded {
			// Expand directory
			currentNode.Expanded = true
			fem.expanded[currentNode.Info.Path] = true
		} else if len(currentNode.Children) > 0 {
			// Move to first child
			fem.selected++
		}
	}
	return fem
}

func (fem FileExplorerModel) toggleExpanded() FileExplorerModel {
	currentNode := fem.getSelectedNode()
	if currentNode != nil && currentNode.Info.Type == "directory" {
		currentNode.Expanded = !currentNode.Expanded
		fem.expanded[currentNode.Info.Path] = currentNode.Expanded
	}
	return fem
}

// Helper methods
func (fem FileExplorerModel) getSelectedNode() *FileNode {
	lines := fem.renderTree(fem.tree, 0)
	if fem.selected < len(lines) {
		// This is simplified - in a real implementation, 
		// you'd maintain a mapping between line index and node
		return fem.findNodeByIndex(fem.tree, fem.selected, 0)
	}
	return nil
}

func (fem FileExplorerModel) findNodeByIndex(node *FileNode, targetIndex, currentIndex int) *FileNode {
	if node == nil {
		return nil
	}
	
	if node.Level >= 0 {
		if currentIndex == targetIndex {
			return node
		}
		currentIndex++
	}
	
	if node.Expanded || node.Level < 0 {
		for _, child := range node.Children {
			if result := fem.findNodeByIndex(child, targetIndex, currentIndex); result != nil {
				return result
			}
			currentIndex += fem.countVisibleNodes(child)
		}
	}
	
	return nil
}

func (fem FileExplorerModel) countVisibleNodes(node *FileNode) int {
	if node == nil {
		return 0
	}
	
	count := 1
	if node.Expanded {
		for _, child := range node.Children {
			count += fem.countVisibleNodes(child)
		}
	}
	
	return count
}

func (fem FileExplorerModel) getNodeIndex(targetNode *FileNode) int {
	return fem.findNodeIndex(fem.tree, targetNode, 0)
}

func (fem FileExplorerModel) findNodeIndex(node *FileNode, target *FileNode, currentIndex int) int {
	if node == nil {
		return -1
	}
	
	if node.Level >= 0 {
		if node == target {
			return currentIndex
		}
		currentIndex++
	}
	
	if node.Expanded || node.Level < 0 {
		for _, child := range node.Children {
			if index := fem.findNodeIndex(child, target, currentIndex); index != -1 {
				return index
			}
			currentIndex += fem.countVisibleNodes(child)
		}
	}
	
	return -1
}

// Additional methods for commands
func (fem FileExplorerModel) selectFile() tea.Cmd {
	currentNode := fem.getSelectedNode()
	if currentNode != nil {
		return func() tea.Msg {
			return FileSelectedMsg{Path: currentNode.Info.Path}
		}
	}
	return nil
}

func (fem FileExplorerModel) openFile() tea.Cmd {
	currentNode := fem.getSelectedNode()
	if currentNode != nil && currentNode.Info.Type == "file" {
		return func() tea.Msg {
			return OpenFileMsg{Path: currentNode.Info.Path}
		}
	}
	return nil
}

func (fem FileExplorerModel) refreshFiles() tea.Cmd {
	return func() tea.Msg {
		return RefreshFilesMsg{Path: fem.rootPath}
	}
}

func (fem FileExplorerModel) createNewFile() tea.Cmd {
	currentNode := fem.getSelectedNode()
	path := fem.rootPath
	if currentNode != nil {
		if currentNode.Info.Type == "directory" {
			path = currentNode.Info.Path
		} else {
			path = filepath.Dir(currentNode.Info.Path)
		}
	}
	return func() tea.Msg {
		return CreateFileMsg{Path: path}
	}
}

func (fem FileExplorerModel) deleteFile() tea.Cmd {
	currentNode := fem.getSelectedNode()
	if currentNode != nil {
		return func() tea.Msg {
			return DeleteFileMsg{Path: currentNode.Info.Path}
		}
	}
	return nil
}

// Additional utility methods
func (fem FileExplorerModel) getVisibleFileCount() int {
	if fem.tree == nil {
		return 0
	}
	return fem.countVisibleNodes(fem.tree) - 1 // Exclude root
}

func (fem FileExplorerModel) getVisibleLines(lines []string) []string {
	if len(lines) == 0 {
		return lines
	}
	
	maxVisible := fem.height - 4 // Account for header, separator, and status
	if maxVisible <= 0 {
		return []string{}
	}
	
	start := fem.viewport.offset
	end := start + maxVisible
	
	if end > len(lines) {
		end = len(lines)
	}
	
	if start >= len(lines) {
		start = len(lines) - 1
		if start < 0 {
			start = 0
		}
	}
	
	return lines[start:end]
}

func (fem FileExplorerModel) adjustViewport() {
	maxVisible := fem.height - 4
	if maxVisible <= 0 {
		return
	}
	
	// Ensure selected item is visible
	if fem.selected < fem.viewport.offset {
		fem.viewport.offset = fem.selected
	} else if fem.selected >= fem.viewport.offset+maxVisible {
		fem.viewport.offset = fem.selected - maxVisible + 1
	}
}

func (fem FileExplorerModel) toggleFilter() FileExplorerModel {
	if fem.filter == "" {
		fem.filter = " " // Start filter mode
	} else {
		fem.filter = ""
	}
	return fem
}

func (fem FileExplorerModel) applyFilter() FileExplorerModel {
	// Filter logic would be implemented here
	return fem
}

func (fem FileExplorerModel) sortFiles() FileExplorerModel {
	if fem.tree != nil {
		fem.tree = fem.buildTree(fem.files)
	}
	return fem
}

func (fem FileExplorerModel) renderTitle(title string) string {
	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("63")).
		Bold(true).
		Render(title)
}

func (fem FileExplorerModel) renderStatusLine() string {
	sortName := []string{"Name", "Type", "Size", "Modified"}[fem.sortBy]
	status := fmt.Sprintf("Sort: %s | Files: %d", sortName, fem.getVisibleFileCount())
	
	if fem.showHidden {
		status += " | Hidden: ✓"
	}
	
	return lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Render(status)
}

// Additional message types
type FileTreeUpdatedMsg struct {
	Files []types.FileInfo
}

type FileOperationCompletedMsg struct {
	Operation string
	Path      string
	Success   bool
}

type OpenFileMsg struct {
	Path string
}

type RefreshFilesMsg struct {
	Path string
}

type CreateFileMsg struct {
	Path string
}

type DeleteFileMsg struct {
	Path string
}