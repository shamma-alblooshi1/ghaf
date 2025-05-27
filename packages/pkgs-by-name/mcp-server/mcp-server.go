// Copyright 2024 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Message represents a communication between agents
type Message struct {
	ID        string                 `json:"id"`
	Sender    string                 `json:"sender"`
	Recipient string                 `json:"recipient"`
	Content   map[string]interface{} `json:"content"`
	Timestamp int64                  `json:"timestamp"`
}

// Server represents the MCP server
type Server struct {
	messages      []Message
	agents        map[string]bool
	mutex         sync.RWMutex
	stateDir      string
	subscriptions map[string][]chan Message
	subMutex      sync.RWMutex
}

func NewServer(stateDir string) *Server {
	return &Server{
		messages:      []Message{},
		agents:        make(map[string]bool),
		stateDir:      stateDir,
		subscriptions: make(map[string][]chan Message),
	}
}

func (s *Server) registerAgent(w http.ResponseWriter, r *http.Request) {
	var agent struct {
		ID string `json:"id"`
	}
	
	if err := json.NewDecoder(r.Body).Decode(&agent); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	
	s.mutex.Lock()
	s.agents[agent.ID] = true
	s.mutex.Unlock()
	
	log.Printf("Agent registered: %s", agent.ID)
	w.WriteHeader(http.StatusCreated)
}

func (s *Server) sendMessage(w http.ResponseWriter, r *http.Request) {
	var msg Message
	
	if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
		http.Error(w, "Invalid message format", http.StatusBadRequest)
		return
	}
	
	// Set timestamp if not provided
	if msg.Timestamp == 0 {
		msg.Timestamp = time.Now().UnixNano() / int64(time.Millisecond)
	}
	
	s.mutex.Lock()
	s.messages = append(s.messages, msg)
	s.mutex.Unlock()
	
	// Notify subscribers
	s.subMutex.RLock()
	if channels, ok := s.subscriptions[msg.Recipient]; ok {
		for _, ch := range channels {
			select {
			case ch <- msg:
				// Message sent
			default:
				// Channel buffer full, skip
			}
		}
	}
	s.subMutex.RUnlock()
	
	log.Printf("Message sent from %s to %s", msg.Sender, msg.Recipient)
	w.WriteHeader(http.StatusCreated)
}

func (s *Server) getMessages(w http.ResponseWriter, r *http.Request) {
	recipient := r.URL.Query().Get("recipient")
	if recipient == "" {
		http.Error(w, "Recipient parameter is required", http.StatusBadRequest)
		return
	}
	
	s.mutex.RLock()
	var messages []Message
	for _, msg := range s.messages {
		if msg.Recipient == recipient {
			messages = append(messages, msg)
		}
	}
	s.mutex.RUnlock()
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(messages)
}

func (s *Server) subscribeToMessages(w http.ResponseWriter, r *http.Request) {
	recipient := r.URL.Query().Get("recipient")
	if recipient == "" {
		http.Error(w, "Recipient parameter is required", http.StatusBadRequest)
		return
	}
	
	// Set up SSE
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	
	// Create channel for this subscription
	messageChan := make(chan Message, 10)
	
	// Register subscription
	s.subMutex.Lock()
	if _, exists := s.subscriptions[recipient]; !exists {
		s.subscriptions[recipient] = []chan Message{}
	}
	s.subscriptions[recipient] = append(s.subscriptions[recipient], messageChan)
	s.subMutex.Unlock()
	
	// Clean up when connection is closed
	notify := r.Context().Done()
	go func() {
		<-notify
		s.subMutex.Lock()
		defer s.subMutex.Unlock()
		
		channels := s.subscriptions[recipient]
		for i, ch := range channels {
			if ch == messageChan {
				// Remove this channel
				s.subscriptions[recipient] = append(channels[:i], channels[i+1:]...)
				close(ch)
				break
			}
		}
	}()
	
	// Send messages as they arrive
	for msg := range messageChan {
		data, err := json.Marshal(msg)
		if err != nil {
			continue
		}
		fmt.Fprintf(w, "data: %s\n\n", data)
		if f, ok := w.(http.Flusher); ok {
			f.Flush()
		}
	}
}

func (s *Server) saveState() error {
	s.mutex.RLock()
	defer s.mutex.RUnlock()
	
	state := struct {
		Messages []Message        `json:"messages"`
		Agents   map[string]bool `json:"agents"`
	}{
		Messages: s.messages,
		Agents:   s.agents,
	}
	
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	
	stateFile := filepath.Join(s.stateDir, "mcp-state.json")
	return os.WriteFile(stateFile, data, 0640)
}

func main() {
	port := flag.Int("port", 1337, "Port to listen on")
	host := flag.String("host", "127.0.0.1", "Host address to bind to")
	logLevel := flag.String("log-level", "info", "Log level (debug, info, warning, error)")
	stateDir := flag.String("state-dir", "/var/lib/mcp-server", "Directory to store state")
	flag.Parse()
	
	// Configure logging
	switch *logLevel {
	case "debug":
		log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	case "info":
		log.SetFlags(log.Ldate | log.Ltime)
	case "warning", "error":
		log.SetFlags(log.Ldate | log.Ltime)
	}
	
	// Ensure state directory exists
	if err := os.MkdirAll(*stateDir, 0750); err != nil {
		log.Fatalf("Failed to create state directory: %v", err)
	}
	
	server := NewServer(*stateDir)
	
	// Load existing state if available
	stateFile := filepath.Join(*stateDir, "mcp-state.json")
	if data, err := os.ReadFile(stateFile); err == nil {
		var state struct {
			Messages []Message        `json:"messages"`
			Agents   map[string]bool `json:"agents"`
		}
		if err := json.Unmarshal(data, &state); err == nil {
			server.mutex.Lock()
			server.messages = state.Messages
			server.agents = state.Agents
			server.mutex.Unlock()
			log.Println("Loaded existing state")
		}
	}
	
	// Set up HTTP routes
	http.HandleFunc("/agents", server.registerAgent)
	http.HandleFunc("/messages", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodPost:
			server.sendMessage(w, r)
		case http.MethodGet:
			server.getMessages(w, r)
		default:
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})
	http.HandleFunc("/subscribe", server.subscribeToMessages)
	
	// Periodically save state
	go func() {
		ticker := time.NewTicker(1 * time.Minute)
		defer ticker.Stop()
		
		for range ticker.C {
			if err := server.saveState(); err != nil {
				log.Printf("Failed to save state: %v", err)
			}
		}
	}()
	
	// Start server
	addr := fmt.Sprintf("%s:%d", *host, *port)
	log.Printf("MCP server starting on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
