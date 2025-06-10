package ui

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// FocusManager handles panel focus state and visual indicators
type FocusManager struct {
	currentPanel   PanelType
	previousPanel  PanelType
	focusHistory   []PanelType
	focusRing      []PanelType
	visualStyle    FocusVisualStyle
	transitionTime time.Duration
	lastChange     time.Time
	animations     map[PanelType]*FocusAnimation
}

// FocusVisualStyle defines the visual styling for focused panels
type FocusVisualStyle struct {
	BorderFocused   lipgloss.Border
	BorderUnfocused lipgloss.Border
	ColorFocused    lipgloss.Color
	ColorUnfocused  lipgloss.Color
	ColorHighlight  lipgloss.Color
	GlowEffect      bool
	AnimationSpeed  time.Duration
}

// FocusAnimation represents an animation state for focus transitions
type FocusAnimation struct {
	startTime   time.Time
	duration    time.Duration
	fromStyle   lipgloss.Style
	toStyle     lipgloss.Style
	easing      EasingFunction
}

// EasingFunction defines animation easing
type EasingFunction func(t float64) float64

// PanelFocusState represents the focus state of a panel
type PanelFocusState struct {
	Panel    PanelType
	Focused  bool
	Style    lipgloss.Style
	Duration time.Duration
}

// NewFocusManager creates a new focus manager
func NewFocusManager() *FocusManager {
	focusRing := []PanelType{
		FileTreePanel,
		EditorPanel,
		ChatPanel,
		ContextPanel,
	}
	
	visualStyle := FocusVisualStyle{
		BorderFocused:   lipgloss.RoundedBorder(),
		BorderUnfocused: lipgloss.NormalBorder(),
		ColorFocused:    lipgloss.Color("63"),  // Blue
		ColorUnfocused:  lipgloss.Color("241"), // Gray
		ColorHighlight:  lipgloss.Color("205"), // Pink
		GlowEffect:      true,
		AnimationSpeed:  200 * time.Millisecond,
	}
	
	return &FocusManager{
		currentPanel:   FileTreePanel,
		focusHistory:   make([]PanelType, 0, 10),
		focusRing:      focusRing,
		visualStyle:    visualStyle,
		transitionTime: 200 * time.Millisecond,
		lastChange:     time.Now(),
		animations:     make(map[PanelType]*FocusAnimation),
	}
}

// SetFocus changes focus to the specified panel
func (fm *FocusManager) SetFocus(panel PanelType) tea.Cmd {
	if fm.currentPanel == panel {
		return nil
	}
	
	// Record previous panel
	fm.previousPanel = fm.currentPanel
	
	// Add to history
	fm.addToHistory(fm.currentPanel)
	
	// Start focus transition animation
	cmd := fm.startFocusTransition(fm.currentPanel, panel)
	
	// Update current panel
	fm.currentPanel = panel
	fm.lastChange = time.Now()
	
	return cmd
}

// FocusNext moves focus to the next panel in the ring
func (fm *FocusManager) FocusNext() tea.Cmd {
	currentIndex := fm.findPanelIndex(fm.currentPanel)
	nextIndex := (currentIndex + 1) % len(fm.focusRing)
	nextPanel := fm.focusRing[nextIndex]
	
	return fm.SetFocus(nextPanel)
}

// FocusPrevious moves focus to the previous panel in the ring
func (fm *FocusManager) FocusPrevious() tea.Cmd {
	currentIndex := fm.findPanelIndex(fm.currentPanel)
	prevIndex := (currentIndex - 1 + len(fm.focusRing)) % len(fm.focusRing)
	prevPanel := fm.focusRing[prevIndex]
	
	return fm.SetFocus(prevPanel)
}

// FocusLast returns focus to the previously focused panel
func (fm *FocusManager) FocusLast() tea.Cmd {
	if fm.previousPanel != fm.currentPanel {
		return fm.SetFocus(fm.previousPanel)
	}
	
	// Fall back to history
	if len(fm.focusHistory) > 0 {
		lastPanel := fm.focusHistory[len(fm.focusHistory)-1]
		fm.focusHistory = fm.focusHistory[:len(fm.focusHistory)-1]
		return fm.SetFocus(lastPanel)
	}
	
	return nil
}

// GetCurrentFocus returns the currently focused panel
func (fm *FocusManager) GetCurrentFocus() PanelType {
	return fm.currentPanel
}

// IsFocused returns true if the specified panel is currently focused
func (fm *FocusManager) IsFocused(panel PanelType) bool {
	return fm.currentPanel == panel
}

// GetPanelStyle returns the appropriate style for a panel based on focus state
func (fm *FocusManager) GetPanelStyle(panel PanelType, width, height int) lipgloss.Style {
	baseStyle := lipgloss.NewStyle().
		Width(width).
		Height(height).
		Padding(0, 1)
	
	focused := fm.IsFocused(panel)
	
	// Check for active animation
	if animation, exists := fm.animations[panel]; exists {
		return fm.getAnimatedStyle(animation, baseStyle)
	}
	
	// Apply focus styling
	if focused {
		return baseStyle.
			BorderStyle(fm.visualStyle.BorderFocused).
			BorderForeground(fm.visualStyle.ColorFocused)
	} else {
		return baseStyle.
			BorderStyle(fm.visualStyle.BorderUnfocused).
			BorderForeground(fm.visualStyle.ColorUnfocused)
	}
}

// GetFocusIndicator returns a visual focus indicator for a panel
func (fm *FocusManager) GetFocusIndicator(panel PanelType) string {
	if !fm.IsFocused(panel) {
		return ""
	}
	
	// Create animated focus indicator
	timeSinceFocus := time.Since(fm.lastChange)
	if timeSinceFocus < fm.transitionTime {
		// Show transition animation
		progress := float64(timeSinceFocus) / float64(fm.transitionTime)
		intensity := fm.easeInOut(progress)
		
		if intensity > 0.5 {
			return "●" // Strong indicator
		} else {
			return "○" // Weak indicator
		}
	}
	
	return "●" // Steady indicator
}

// GetPanelTitle returns a styled title for a panel
func (fm *FocusManager) GetPanelTitle(panel PanelType, title string) string {
	focused := fm.IsFocused(panel)
	
	style := lipgloss.NewStyle().Bold(true)
	
	if focused {
		style = style.Foreground(fm.visualStyle.ColorFocused)
		
		// Add focus indicator
		indicator := fm.GetFocusIndicator(panel)
		if indicator != "" {
			title = indicator + " " + title
		}
	} else {
		style = style.Foreground(fm.visualStyle.ColorUnfocused)
	}
	
	return style.Render(title)
}

// Update handles focus manager updates (animations, etc.)
func (fm *FocusManager) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case AnimationTickMsg:
		return fm, fm.updateAnimations()
		
	case FocusTransitionCompleteMsg:
		delete(fm.animations, msg.Panel)
		return fm, nil
	}
	
	return fm, nil
}

// startFocusTransition begins a focus transition animation
func (fm *FocusManager) startFocusTransition(from, to PanelType) tea.Cmd {
	if !fm.visualStyle.GlowEffect {
		return nil
	}
	
	// Create animations for both panels
	now := time.Now()
	duration := fm.visualStyle.AnimationSpeed
	
	// Animation for panel losing focus
	fm.animations[from] = &FocusAnimation{
		startTime: now,
		duration:  duration,
		fromStyle: lipgloss.NewStyle().BorderForeground(fm.visualStyle.ColorFocused),
		toStyle:   lipgloss.NewStyle().BorderForeground(fm.visualStyle.ColorUnfocused),
		easing:    fm.easeOut,
	}
	
	// Animation for panel gaining focus
	fm.animations[to] = &FocusAnimation{
		startTime: now,
		duration:  duration,
		fromStyle: lipgloss.NewStyle().BorderForeground(fm.visualStyle.ColorUnfocused),
		toStyle:   lipgloss.NewStyle().BorderForeground(fm.visualStyle.ColorFocused),
		easing:    fm.easeIn,
	}
	
	// Start animation ticker
	return tea.Tick(16*time.Millisecond, func(t time.Time) tea.Msg {
		return AnimationTickMsg{Time: t}
	})
}

// updateAnimations updates all active animations
func (fm *FocusManager) updateAnimations() tea.Cmd {
	now := time.Now()
	activeAnimations := false
	
	for panel, animation := range fm.animations {
		elapsed := now.Sub(animation.startTime)
		
		if elapsed >= animation.duration {
			// Animation complete
			delete(fm.animations, panel)
			// Send completion message
			return func() tea.Msg {
				return FocusTransitionCompleteMsg{Panel: panel}
			}
		} else {
			activeAnimations = true
		}
	}
	
	// Continue animation if any are still active
	if activeAnimations {
		return tea.Tick(16*time.Millisecond, func(t time.Time) tea.Msg {
			return AnimationTickMsg{Time: t}
		})
	}
	
	return nil
}

// getAnimatedStyle returns an interpolated style for an active animation
func (fm *FocusManager) getAnimatedStyle(animation *FocusAnimation, baseStyle lipgloss.Style) lipgloss.Style {
	now := time.Now()
	elapsed := now.Sub(animation.startTime)
	progress := float64(elapsed) / float64(animation.duration)
	
	if progress >= 1.0 {
		return baseStyle.Copy().Inherit(animation.toStyle)
	}
	
	// Apply easing
	easedProgress := animation.easing(progress)
	
	// Interpolate border color (simplified)
	if easedProgress < 0.5 {
		return baseStyle.Copy().Inherit(animation.fromStyle)
	} else {
		return baseStyle.Copy().Inherit(animation.toStyle)
	}
}

// Easing functions for smooth animations
func (fm *FocusManager) easeIn(t float64) float64 {
	return t * t
}

func (fm *FocusManager) easeOut(t float64) float64 {
	return 1 - (1-t)*(1-t)
}

func (fm *FocusManager) easeInOut(t float64) float64 {
	if t < 0.5 {
		return 2 * t * t
	}
	return 1 - 2*(1-t)*(1-t)
}

// Helper methods
func (fm *FocusManager) findPanelIndex(panel PanelType) int {
	for i, p := range fm.focusRing {
		if p == panel {
			return i
		}
	}
	return 0
}

func (fm *FocusManager) addToHistory(panel PanelType) {
	// Avoid duplicates
	if len(fm.focusHistory) > 0 && fm.focusHistory[len(fm.focusHistory)-1] == panel {
		return
	}
	
	fm.focusHistory = append(fm.focusHistory, panel)
	
	// Limit history size
	if len(fm.focusHistory) > 10 {
		fm.focusHistory = fm.focusHistory[1:]
	}
}

// SetFocusRing customizes the focus navigation order
func (fm *FocusManager) SetFocusRing(panels []PanelType) {
	fm.focusRing = make([]PanelType, len(panels))
	copy(fm.focusRing, panels)
}

// SetVisualStyle customizes the visual styling
func (fm *FocusManager) SetVisualStyle(style FocusVisualStyle) {
	fm.visualStyle = style
}

// GetFocusHistory returns the focus history
func (fm *FocusManager) GetFocusHistory() []PanelType {
	history := make([]PanelType, len(fm.focusHistory))
	copy(history, fm.focusHistory)
	return history
}

// EnableAnimations enables or disables focus animations
func (fm *FocusManager) EnableAnimations(enabled bool) {
	fm.visualStyle.GlowEffect = enabled
	if !enabled {
		// Clear any active animations
		fm.animations = make(map[PanelType]*FocusAnimation)
	}
}

// SetTransitionTime sets the focus transition duration
func (fm *FocusManager) SetTransitionTime(duration time.Duration) {
	fm.transitionTime = duration
	fm.visualStyle.AnimationSpeed = duration
}

// Focus state queries
func (fm *FocusManager) HasFocusChanged(since time.Time) bool {
	return fm.lastChange.After(since)
}

func (fm *FocusManager) GetFocusDuration() time.Duration {
	return time.Since(fm.lastChange)
}

func (fm *FocusManager) IsTransitioning() bool {
	return len(fm.animations) > 0
}

// Keyboard shortcuts for common focus operations
func (fm *FocusManager) HandleFocusShortcut(key string) tea.Cmd {
	switch key {
	case "tab":
		return fm.FocusNext()
	case "shift+tab":
		return fm.FocusPrevious()
	case "alt+tab":
		return fm.FocusLast()
	case "ctrl+1":
		return fm.SetFocus(FileTreePanel)
	case "ctrl+2":
		return fm.SetFocus(EditorPanel)
	case "ctrl+3":
		return fm.SetFocus(ChatPanel)
	case "ctrl+4":
		return fm.SetFocus(ContextPanel)
	default:
		return nil
	}
}

// Message types for focus management
type AnimationTickMsg struct {
	Time time.Time
}

type FocusTransitionCompleteMsg struct {
	Panel PanelType
}

type FocusChangedMsg struct {
	From PanelType
	To   PanelType
}

// PanelVisibility manages panel visibility based on layout mode
type PanelVisibility struct {
	fileTree bool
	editor   bool
	chat     bool
	context  bool
}

func (fm *FocusManager) GetPanelVisibility(layoutMode LayoutMode) PanelVisibility {
	switch layoutMode {
	case LayoutModeCompact:
		// In compact mode, only show one panel at a time
		return PanelVisibility{
			fileTree: fm.currentPanel == FileTreePanel,
			editor:   fm.currentPanel == EditorPanel,
			chat:     fm.currentPanel == ChatPanel,
			context:  fm.currentPanel == ContextPanel,
		}
		
	case LayoutModeStandard:
		// In standard mode, show main panels
		return PanelVisibility{
			fileTree: true,
			editor:   true,
			chat:     true,
			context:  false, // Hide context panel in standard mode
		}
		
	case LayoutModeExpanded:
		// In expanded mode, show all panels
		return PanelVisibility{
			fileTree: true,
			editor:   true,
			chat:     true,
			context:  true,
		}
		
	default:
		return PanelVisibility{
			fileTree: true,
			editor:   true,
			chat:     true,
			context:  false,
		}
	}
}

// Focus context for panels
type FocusContext struct {
	Panel       PanelType
	Focused     bool
	CanReceive  bool
	LastFocused time.Time
}

func (fm *FocusManager) GetFocusContext(panel PanelType) FocusContext {
	return FocusContext{
		Panel:       panel,
		Focused:     fm.IsFocused(panel),
		CanReceive:  fm.canReceiveFocus(panel),
		LastFocused: fm.getLastFocusTime(panel),
	}
}

func (fm *FocusManager) canReceiveFocus(panel PanelType) bool {
	// All panels can receive focus by default
	// This could be extended to handle disabled panels
	return true
}

func (fm *FocusManager) getLastFocusTime(panel PanelType) time.Time {
	if panel == fm.currentPanel {
		return fm.lastChange
	}
	
	// This could be extended to track per-panel focus times
	return time.Time{}
}