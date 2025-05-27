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
            exec ${bash}/bin/bash $out/bin/${name}-handler handle-request --state-dir "$STATE_DIR"
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
    name = "${name}-handler";
    executable = true;
    text = builtins.readFile ./mcp-server-handler.nix;
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
    chmod +x $out/bin/${name}-handler
    ${makeWrapper}/bin/makeWrapper $out/bin/${name}-script $out/bin/${name} \
      --prefix PATH : ${lib.makeBinPath [ coreutils jq socat bash ]}
    ${makeWrapper}/bin/makeWrapper $out/bin/${name}-handler $out/bin/${name}-handler.wrapped \
      --prefix PATH : ${lib.makeBinPath [ coreutils jq socat bash ]}
    mv $out/bin/${name}-handler.wrapped $out/bin/${name}-handler
  '';
  
  meta = with lib; {
    description = "Message Control Protocol server for AI agents";
    license = licenses.apache20;
    maintainers = with maintainers; [ ];
    mainProgram = "mcp-server";
  };
}
