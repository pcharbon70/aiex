package ui

import (
	"math"

	"github.com/charmbracelet/lipgloss"
)

// LayoutManager handles responsive layout calculations and panel sizing
type LayoutManager struct {
	width  int
	height int
	config LayoutConfig
}

// ResponsiveBreakpoints define screen size breakpoints for responsive design
type ResponsiveBreakpoints struct {
	Small  int // < 80 columns
	Medium int // 80-120 columns  
	Large  int // > 120 columns
}

var breakpoints = ResponsiveBreakpoints{
	Small:  80,
	Medium: 120,
	Large:  150,
}

// NewLayoutManager creates a new layout manager
func NewLayoutManager(width, height int, config LayoutConfig) *LayoutManager {
	return &LayoutManager{
		width:  width,
		height: height,
		config: config,
	}
}

// UpdateDimensions updates the layout dimensions
func (lm *LayoutManager) UpdateDimensions(width, height int) {
	lm.width = width
	lm.height = height
	
	// Adjust layout config based on screen size
	lm.adjustForScreenSize()
}

// adjustForScreenSize adapts the layout configuration based on screen dimensions
func (lm *LayoutManager) adjustForScreenSize() {
	switch {
	case lm.width < breakpoints.Small:
		// Small screen: hide sidebar by default, single panel view
		lm.config.ShowSidebar = false
		lm.config.ShowContext = false
		lm.config.SidebarWidth = 0
		lm.config.EditorRatio = 1.0
		lm.config.ChatRatio = 0.0
		
	case lm.width < breakpoints.Medium:
		// Medium screen: smaller sidebar, adjust ratios
		lm.config.SidebarWidth = 25
		lm.config.EditorRatio = 0.7
		lm.config.ChatRatio = 0.3
		
	case lm.width < breakpoints.Large:
		// Large screen: standard layout
		lm.config.SidebarWidth = 30
		lm.config.EditorRatio = 0.6
		lm.config.ChatRatio = 0.4
		
	default:
		// Extra large screen: wider sidebar, more space
		lm.config.SidebarWidth = 35
		lm.config.EditorRatio = 0.55
		lm.config.ChatRatio = 0.45
	}
}

// CalculatePanelDimensions returns the calculated dimensions for all panels
func (lm *LayoutManager) CalculatePanelDimensions() PanelDimensions {
	headerHeight := 1
	statusHeight := 1
	availableHeight := lm.height - headerHeight - statusHeight
	
	sidebarWidth := 0
	if lm.config.ShowSidebar {
		sidebarWidth = lm.config.SidebarWidth
	}
	
	mainAreaWidth := lm.width - sidebarWidth
	if mainAreaWidth < 0 {
		mainAreaWidth = 0
	}
	
	// Calculate editor and chat widths
	editorWidth := int(float64(mainAreaWidth) * lm.config.EditorRatio)
	chatWidth := mainAreaWidth - editorWidth
	
	// Ensure minimum widths
	minPanelWidth := 20
	if editorWidth < minPanelWidth && chatWidth > minPanelWidth {
		editorWidth = minPanelWidth
		chatWidth = mainAreaWidth - editorWidth
	} else if chatWidth < minPanelWidth && editorWidth > minPanelWidth {
		chatWidth = minPanelWidth
		editorWidth = mainAreaWidth - chatWidth
	}
	
	return PanelDimensions{
		Header: Dimensions{Width: lm.width, Height: headerHeight},
		Status: Dimensions{Width: lm.width, Height: statusHeight},
		Sidebar: Dimensions{Width: sidebarWidth, Height: availableHeight},
		Editor: Dimensions{Width: editorWidth, Height: availableHeight},
		Chat: Dimensions{Width: chatWidth, Height: availableHeight},
		Context: Dimensions{Width: sidebarWidth, Height: availableHeight},
	}
}

// GetLayoutMode returns the current layout mode based on screen size
func (lm *LayoutManager) GetLayoutMode() LayoutMode {
	switch {
	case lm.width < breakpoints.Small:
		return LayoutModeCompact
	case lm.width < breakpoints.Medium:
		return LayoutModeStandard
	default:
		return LayoutModeExpanded
	}
}

// PanelDimensions holds dimensions for all panels
type PanelDimensions struct {
	Header  Dimensions
	Status  Dimensions
	Sidebar Dimensions
	Editor  Dimensions
	Chat    Dimensions
	Context Dimensions
}

// Dimensions represents width and height
type Dimensions struct {
	Width  int
	Height int
}

// LayoutMode represents different layout modes
type LayoutMode int

const (
	LayoutModeCompact LayoutMode = iota
	LayoutModeStandard
	LayoutModeExpanded
)

// StyleManager handles consistent styling across panels
type StyleManager struct {
	theme Theme
	mode  LayoutMode
}

// Theme defines the color scheme and styling
type Theme struct {
	Primary       lipgloss.Color
	Secondary     lipgloss.Color
	Accent        lipgloss.Color
	Background    lipgloss.Color
	Surface       lipgloss.Color
	OnPrimary     lipgloss.Color
	OnSecondary   lipgloss.Color
	OnBackground  lipgloss.Color
	Border        lipgloss.Color
	BorderFocused lipgloss.Color
	Error         lipgloss.Color
	Warning       lipgloss.Color
	Success       lipgloss.Color
	Info          lipgloss.Color
}

// Default themes
var (
	DarkTheme = Theme{
		Primary:       lipgloss.Color("63"),   // Blue
		Secondary:     lipgloss.Color("240"),  // Gray
		Accent:        lipgloss.Color("205"),  // Pink
		Background:    lipgloss.Color("235"), // Dark gray
		Surface:       lipgloss.Color("237"), // Slightly lighter gray
		OnPrimary:     lipgloss.Color("230"), // Light gray
		OnSecondary:   lipgloss.Color("250"), // Lighter gray
		OnBackground:  lipgloss.Color("255"), // White
		Border:        lipgloss.Color("241"), // Medium gray
		BorderFocused: lipgloss.Color("63"),  // Blue
		Error:         lipgloss.Color("196"), // Red
		Warning:       lipgloss.Color("214"), // Orange
		Success:       lipgloss.Color("34"),  // Green
		Info:          lipgloss.Color("39"),  // Cyan
	}
	
	LightTheme = Theme{
		Primary:       lipgloss.Color("25"),   // Dark blue
		Secondary:     lipgloss.Color("240"),  // Gray
		Accent:        lipgloss.Color("205"),  // Pink
		Background:    lipgloss.Color("255"), // White
		Surface:       lipgloss.Color("254"), // Light gray
		OnPrimary:     lipgloss.Color("255"), // White
		OnSecondary:   lipgloss.Color("0"),   // Black
		OnBackground:  lipgloss.Color("0"),   // Black
		Border:        lipgloss.Color("240"), // Gray
		BorderFocused: lipgloss.Color("25"),  // Dark blue
		Error:         lipgloss.Color("196"), // Red
		Warning:       lipgloss.Color("214"), // Orange
		Success:       lipgloss.Color("34"),  // Green
		Info:          lipgloss.Color("39"),  // Cyan
	}
)

// NewStyleManager creates a new style manager
func NewStyleManager(theme Theme, mode LayoutMode) *StyleManager {
	return &StyleManager{
		theme: theme,
		mode:  mode,
	}
}

// GetPanelStyle returns the base style for a panel
func (sm *StyleManager) GetPanelStyle(focused bool, width, height int) lipgloss.Style {
	style := lipgloss.NewStyle().
		Width(width).
		Height(height).
		Background(sm.theme.Surface).
		Foreground(sm.theme.OnBackground).
		Padding(0, 1)
	
	if focused {
		style = style.
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(sm.theme.BorderFocused)
	} else {
		style = style.
			BorderStyle(lipgloss.NormalBorder()).
			BorderForeground(sm.theme.Border)
	}
	
	return style
}

// GetHeaderStyle returns the style for the header
func (sm *StyleManager) GetHeaderStyle(width int) lipgloss.Style {
	return lipgloss.NewStyle().
		Width(width).
		Height(1).
		Background(sm.theme.Primary).
		Foreground(sm.theme.OnPrimary).
		Bold(true).
		Padding(0, 1)
}

// GetStatusStyle returns the style for the status bar
func (sm *StyleManager) GetStatusStyle(width int) lipgloss.Style {
	return lipgloss.NewStyle().
		Width(width).
		Height(1).
		Background(sm.theme.Secondary).
		Foreground(sm.theme.OnSecondary).
		Padding(0, 1)
}

// GetDividerStyle returns the style for dividers
func (sm *StyleManager) GetDividerStyle(height int) lipgloss.Style {
	return lipgloss.NewStyle().
		Width(1).
		Height(height).
		Foreground(sm.theme.Border)
}

// GetTitleStyle returns the style for panel titles
func (sm *StyleManager) GetTitleStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Foreground(sm.theme.Primary).
		Bold(true)
}

// GetErrorStyle returns the style for error messages
func (sm *StyleManager) GetErrorStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Background(sm.theme.Error).
		Foreground(sm.theme.OnPrimary).
		Bold(true).
		Padding(0, 1)
}

// GetSuccessStyle returns the style for success messages
func (sm *StyleManager) GetSuccessStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Background(sm.theme.Success).
		Foreground(sm.theme.OnPrimary).
		Bold(true).
		Padding(0, 1)
}

// GetWarningStyle returns the style for warning messages
func (sm *StyleManager) GetWarningStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Background(sm.theme.Warning).
		Foreground(sm.theme.OnPrimary).
		Bold(true).
		Padding(0, 1)
}

// GetInfoStyle returns the style for info messages
func (sm *StyleManager) GetInfoStyle() lipgloss.Style {
	return lipgloss.NewStyle().
		Background(sm.theme.Info).
		Foreground(sm.theme.OnPrimary).
		Bold(true).
		Padding(0, 1)
}

// Adaptive sizing utilities
func (lm *LayoutManager) GetOptimalSidebarWidth() int {
	// Calculate optimal sidebar width based on screen size
	ratio := 0.25 // 25% of screen width
	optimal := int(float64(lm.width) * ratio)
	
	// Clamp between min and max values
	min := 20
	max := 50
	
	return int(math.Max(float64(min), math.Min(float64(max), float64(optimal))))
}

func (lm *LayoutManager) GetOptimalEditorRatio() float64 {
	// Adjust editor ratio based on screen size
	switch lm.GetLayoutMode() {
	case LayoutModeCompact:
		return 1.0 // Full width on small screens
	case LayoutModeStandard:
		return 0.7 // 70% on medium screens
	default:
		return 0.6 // 60% on large screens
	}
}

func (lm *LayoutManager) ShouldShowPanel(panel PanelType) bool {
	mode := lm.GetLayoutMode()
	
	switch panel {
	case FileTreePanel:
		return mode != LayoutModeCompact || lm.config.ShowSidebar
	case ContextPanel:
		return mode == LayoutModeExpanded && lm.config.ShowContext
	case EditorPanel:
		return true // Always show editor
	case ChatPanel:
		return mode != LayoutModeCompact || !lm.config.ShowSidebar
	default:
		return true
	}
}