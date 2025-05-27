# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, writeTextFile, makeWrapper, coreutils, jq, socat, bash }:

let
  name = "mcp-server";
  version = "0.1.0";
  
  script = writeTextFile {
    name = "${name}-script";
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      # Default configuration
      PORT=1337
      HOST="127.0.0.1"
      LOG_LEVEL="info"
      STATE_DIR="/var/lib/mcp-server"
      
      # Parse command line arguments
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --port)
            PORT="$2"
            shift 2
            ;;
          --host)
            HOST="$2"
            shift 2
            ;;
          --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
          --state-dir)
            STATE_DIR="$2"
            shift 2
            ;;
          handle-request)
            exec ${bash}/bin/bash ${./mcp-server-handler.nix} handle-request --state-dir "$STATE_DIR"
            ;;
          *)
            echo "Unknown option: $1"
            exit 1
            ;;
        esac
      done
      
      # Ensure state directory exists
      mkdir -p "$STATE_DIR"
      
      # Initialize state if it doesn't exist
      STATE_FILE="$STATE_DIR/mcp-state.json"
      if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"messages":[],"agents":{}}' > "$STATE_FILE"
      fi
      
      # Log function
      log() {
        local level="$1"
        local message="$2"
        
        case "$LOG_LEVEL" in
          debug)
            echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message"
            ;;
          info)
            if [[ "$level" != "DEBUG" ]]; then
              echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message"
            fi
            ;;
          warning)
            if [[ "$level" != "DEBUG" && "$level" != "INFO" ]]; then
              echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message"
            fi
            ;;
          error)
            if [[ "$level" == "ERROR" ]]; then
              echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message"
            fi
            ;;
        esac
      }
      
      # Save state periodically
      save_state() {
        while true; do
          sleep 60
          log "INFO" "Saving state to $STATE_FILE"
          # Use flock to avoid race conditions
          flock -x "$STATE_FILE" cat "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
        done
      }
      
      # Start background save process
      save_state &
      SAVE_PID=$!
      
      # Cleanup function
      cleanup() {
        log "INFO" "Shutting down MCP server"
        kill $SAVE_PID 2>/dev/null || true
        exit 0
      }
      
      # Register signal handlers
      trap cleanup SIGINT SIGTERM
      
      # Start HTTP server using socat
      log "INFO" "MCP server starting on $HOST:$PORT"
      
      ${socat}/bin/socat TCP-LISTEN:$PORT,bind=$HOST,fork,reuseaddr EXEC:"$0 handle-request",nofork
    '';
  };
  
  handlerScript = writeTextFile {
    name = "mcp-server-handler.nix";
    text = ''
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
            if [[ -n "''${HEADERS[content-length]:-}" ]]; then
              CONTENT_LENGTH="''${HEADERS[content-length]}"
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
                  AGENT_ID=$(echo "$BODY" | ${jq}/bin/jq -r '.id')
                  if [[ -z "$AGENT_ID" || "$AGENT_ID" == "null" ]]; then
                    echo -e "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nInvalid request body"
                    exit 0
                  fi
                  
                  # Update state
                  flock -x "$STATE_FILE" bash -c "
                    TEMP_FILE=$(mktemp)
                    ${jq}/bin/jq '.agents[\"$AGENT_ID\"] = true' \"$STATE_FILE\" > \"\$TEMP_FILE\"
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
                  if ! echo "$BODY" | ${jq}/bin/jq -e '.sender and .recipient and .content' >/dev/null 2>&1; then
                    echo -e "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nInvalid message format"
                    exit 0
                  fi
                  
                  # Add timestamp if not provided
                  MESSAGE=$(echo "$BODY" | ${jq}/bin/jq '. + {timestamp: (if .timestamp then .timestamp else now * 1000 | floor end)}')
                  
                  # Update state
                  flock -x "$STATE_FILE" bash -c "
                    TEMP_FILE=$(mktemp)
                    ${jq}/bin/jq '.messages += [$MESSAGE]' --argjson MESSAGE '$MESSAGE' \"$STATE_FILE\" > \"\$TEMP_FILE\"
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
                  MESSAGES=$(${jq}/bin/jq -c ".messages | map(select(.recipient == \"$RECIPIENT\"))" "$STATE_FILE")
                  
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
                    NEW_MESSAGES=$(${jq}/bin/jq -c ".messages | map(select(.recipient == \"$RECIPIENT\" and (.timestamp * 1000000) > $LAST_CHECK))" "$STATE_FILE")
                    
                    # Send new messages
                    if [[ "$NEW_MESSAGES" != "[]" ]]; then
                      echo "$NEW_MESSAGES" | ${jq}/bin/jq -c '.[]' | while read -r MSG; do
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
    '';
  };

in
writeTextFile {
  name = "${name}-${version}";
  executable = true;
  destination = "/bin/${name}";
  text = ''
    #!/usr/bin/env bash
    exec ${script}/bin/${name}-script "$@"
  '';
  
  buildCommand = ''
    mkdir -p $out/bin
    cp ${script} $out/bin/${name}-script
    cp ${handlerScript} $out/bin/${name}-handler
    ${makeWrapper}/bin/makeWrapper $out/bin/${name}-script $out/bin/${name} \
      --prefix PATH : ${lib.makeBinPath [ coreutils jq socat bash ]}
  '';
  
  meta = with lib; {
    description = "Message Control Protocol server for AI agents";
    license = licenses.apache20;
    maintainers = with maintainers; [ ];
    mainProgram = "mcp-server";
  };
}
