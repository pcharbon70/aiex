package ui

import "aiex-tui/pkg/types"

// ViewportState represents the viewport state for scrollable content
type ViewportState struct {
	TopIndex    int
	BottomIndex int
	ScrollY     int
	TotalLines  int
}

// CursorPosition represents cursor position in the editor
type CursorPosition struct {
	Line   int
	Column int
}

// Selection represents text selection in the editor
type Selection struct {
	Start CursorPosition
	End   CursorPosition
	Active bool
}

// PanelType represents different types of panels in the UI (alias)
type PanelType = types.PanelType

// Panel constants
const (
	PanelFileExplorer = types.PanelFileExplorer
	PanelCodeEditor   = types.PanelCodeEditor
	PanelChat         = types.PanelChat
	PanelStatus       = types.PanelStatus
)