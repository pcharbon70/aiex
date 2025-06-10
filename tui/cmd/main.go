package main

import (
	"context"
	"fmt"
	"log"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"aiex-tui/internal/ui"
	"aiex-tui/internal/rpc"
)

func main() {
	// Initialize RPC client
	rpcClient := rpc.NewClient([]string{"ws://localhost:4000/socket"})
	
	// Create main application model
	app := ui.NewApp(rpcClient)
	
	// Create Bubble Tea program with alt screen
	p := tea.NewProgram(app, tea.WithAltScreen(), tea.WithMouseCellMotion())
	
	// Setup external event injection for real-time updates
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	
	go func() {
		if err := rpcClient.StartEventStream(ctx, p); err != nil {
			log.Printf("Event stream error: %v", err)
		}
	}()
	
	// Run the program
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running TUI: %v\n", err)
		os.Exit(1)
	}
}