#!/usr/bin/env bash
set -euo pipefail

# Default configuration
STATE_DIR="/var/lib/mcp-server"
STATE_FILE="$STATE_DIR/mcp-state.json"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-dir)
      STATE_DIR="$2"
      STATE_FILE="$STATE_DIR/mcp-state.json"
      shift 2
      ;;
    handle-request)
      # This is the entry point for handling HTTP requests
      # Read the HTTP request
      read -r REQUEST_LINE
      METHOD=$(echo "$REQUEST_LINE" | cut -d' ' -f1)
      PATH=$(echo "$REQUEST_LINE" | cut -d' ' -f2)
      
      # Read headers
      declare -A HEADERS
      while read -r LINE; do
        LINE=$(echo "$LINE" | tr -d '\r\n')
        if [[ -z "$LINE" ]]; then
          break
        fi
        KEY=$(echo "$LINE" | cut -d':' -f1 | tr '[:upper:]' '[:lower:]')
        VALUE=$(echo "$LINE" | cut -d':' -f2- | sed 's/^ //')
        HEADERS["$KEY"]="$VALUE"
      done
      
      # Read body if Content-Length is provided
      BODY=""
      if [[ -n "${HEADERS[content-length]:-}" ]]; then
        CONTENT_LENGTH="${HEADERS[content-length]}"
        if [[ "$CONTENT_LENGTH" -gt 0 ]]; then
          BODY=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
        fi
      fi
      
      # Parse query parameters
      QUERY_PARAMS=""
      if [[ "$PATH" == *"?"* ]]; then
        QUERY_PARAMS=$(echo "$PATH" | cut -d'?' -f2)
        PATH=$(echo "$PATH" | cut -d'?' -f1)
      fi
      
      # Handle routes
      case "$PATH" in
        /agents)
          if [[ "$METHOD" == "POST" ]]; then
            # Register agent
            AGENT_ID=$(echo "$BODY" | jq -r '.id')
            if [[ -z "$AGENT_ID" || "$AGENT_ID" == "null" ]]; then
              echo -e "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nInvalid request body"
              exit 0
            fi
            
            # Update state
            flock -x "$STATE_FILE" bash -c "
              TEMP_FILE=$(mktemp)
              jq '.agents[\"$AGENT_ID\"] = true' \"$STATE_FILE\" > \"\$TEMP_FILE\"
              mv \"\$TEMP_FILE\" \"$STATE_FILE\"
            "
            
            echo -e "HTTP/1.1 201 Created\r\nContent-Type: text/plain\r\n\r\nAgent registered"
          else
            echo -e "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain\r\n\r\nMethod not allowed"
          fi
          ;;
          
        /messages)
          if [[ "$METHOD" == "POST" ]]; then
            # Send message
            # Validate message format
            if ! echo "$BODY" | jq -e '.sender and .recipient and .content' >/dev/null 2>&1; then
              echo -e "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nInvalid message format"
              exit 0
            fi
            
            # Add timestamp if not provided
            MESSAGE=$(echo "$BODY" | jq '. + {timestamp: (if .timestamp then .timestamp else now * 1000 | floor end)}')
            
            # Update state
            flock -x "$STATE_FILE" bash -c "
              TEMP_FILE=$(mktemp)
              jq '.messages += [$MESSAGE]' --argjson MESSAGE '$MESSAGE' \"$STATE_FILE\" > \"\$TEMP_FILE\"
              mv \"\$TEMP_FILE\" \"$STATE_FILE\"
            "
            
            echo -e "HTTP/1.1 201 Created\r\nContent-Type: text/plain\r\n\r\nMessage sent"
            
          elif [[ "$METHOD" == "GET" ]]; then
            # Get messages for recipient
            RECIPIENT=""
            if [[ -n "$QUERY_PARAMS" ]]; then
              RECIPIENT=$(echo "$QUERY_PARAMS" | grep -oP 'recipient=\K[^&]+' || echo "")
            fi
            
            if [[ -z "$RECIPIENT" ]]; then
              echo -e "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nRecipient parameter is required"
              exit 0
            fi
            
            # Get messages for recipient
            MESSAGES=$(jq -c ".messages | map(select(.recipient == \"$RECIPIENT\"))" "$STATE_FILE")
            
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n$MESSAGES"
          else
            echo -e "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain\r\n\r\nMethod not allowed"
          fi
          ;;
          
        /subscribe)
          if [[ "$METHOD" == "GET" ]]; then
            # Subscribe to messages
            RECIPIENT=""
            if [[ -n "$QUERY_PARAMS" ]]; then
              RECIPIENT=$(echo "$QUERY_PARAMS" | grep -oP 'recipient=\K[^&]+' || echo "")
            fi
            
            if [[ -z "$RECIPIENT" ]]; then
              echo -e "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nRecipient parameter is required"
              exit 0
            fi
            
            # Set up SSE headers
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
            
            # Initial message to keep connection alive
            echo -e "data: {\"type\":\"connected\"}\n\n"
            
            # Watch for new messages
            LAST_CHECK=$(date +%s%N)
            
            while true; do
              sleep 1
              
              # Get new messages for recipient
              CURRENT_TIME=$(date +%s%N)
              NEW_MESSAGES=$(jq -c ".messages | map(select(.recipient == \"$RECIPIENT\" and (.timestamp * 1000000) > $LAST_CHECK))" "$STATE_FILE")
              
              # Send new messages
              if [[ "$NEW_MESSAGES" != "[]" ]]; then
                echo "$NEW_MESSAGES" | jq -c '.[]' | while read -r MSG; do
                  echo -e "data: $MSG\n\n"
                done
              fi
              
              LAST_CHECK=$CURRENT_TIME
            done
          else
            echo -e "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain\r\n\r\nMethod not allowed"
          fi
          ;;
          
        *)
          echo -e "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nNot Found"
          ;;
      esac
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done
