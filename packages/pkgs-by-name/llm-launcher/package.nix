# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  libnotify,
  ollama,
  alpaca,
  ghaf-artwork ? null,
  curl,
  jq,
  gnused,
  gawk,
}:
writeShellApplication {
  name = "llm-launcher";
  bashOptions = [ "errexit" ];
  runtimeInputs = [
    libnotify
    ollama
    alpaca
    curl
    jq
    gnused
    gawk
  ];
  text = ''
    # Default model if none specified
    DEFAULT_MODEL="falcon3:10b"
    DEFAULT_MODEL_NAME="Falcon 3"
    
    # List of free models that don't require API keys
    FREE_MODELS=(
      "falcon3:10b:Falcon 3"
      "llama3:8b:Llama 3 8B"
      "gemma:2b:Gemma 2B"
      "gemma:7b:Gemma 7B"
      "mistral:7b:Mistral 7B"
      "phi3:mini:Phi-3 Mini"
      "tinyllama:1.1b:TinyLlama"
    )
    
    # Parse command line arguments
    MODEL="$DEFAULT_MODEL"
    MODEL_NAME="$DEFAULT_MODEL_NAME"
    LIST_MODELS=0
    
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --model|-m)
          MODEL="$2"
          shift 2
          ;;
        --list|-l)
          LIST_MODELS=1
          shift
          ;;
        --help|-h)
          echo "Usage: llm-launcher [OPTIONS]"
          echo "Options:"
          echo "  --model, -m MODEL   Specify the model to use (default: $DEFAULT_MODEL)"
          echo "  --list, -l          List available free models"
          echo "  --help, -h          Show this help message"
          exit 0
          ;;
        *)
          echo "Unknown option: $1"
          exit 1
          ;;
      esac
    done
    
    # Function to list available models
    list_available_models() {
      echo "Available free models:"
      for model_info in "''${FREE_MODELS[@]}"; do
        IFS=':' read -r model_id _size model_name <<< "$model_info"
        echo "  $model_id - $model_name"
      done
      
      echo -e "\nInstalled models:"
      ollama list | tail -n +2 | awk '{print "  " $1}'
      exit 0
    }
    
    # Show model list if requested
    if [[ $LIST_MODELS -eq 1 ]]; then
      list_available_models
    fi
    
    # Find model name for the selected model
    for model_info in "''${FREE_MODELS[@]}"; do
      IFS=':' read -r model_id _size model_name <<< "$model_info"
      if [[ "$MODEL" == "$model_id" ]]; then
        MODEL_NAME="$model_name"
        break
      fi
    done
    
    # Set up variables
    DOWNLOAD_FLAG="/tmp/llm-download-$MODEL"
    AI_ICON_PATH=${
      if ghaf-artwork != null then "${ghaf-artwork}/icons/falcon-icon.svg" else "ai-icon"
    }
    NOTIFICATION_ID=
    TMP_LOG=
    
    cleanup() {
        echo 0 > "$DOWNLOAD_FLAG"
        rm "$TMP_LOG" 2>/dev/null
    }
    
    trap cleanup EXIT
    
    # If model is already installed, launch Alpaca
    if ollama show "$MODEL" &>/dev/null; then
        echo "$MODEL is already installed"
        alpaca --model "$MODEL"
        exit 0
    fi
    
    # If download is already ongoing, wait for it to finish
    if [[ -f "$DOWNLOAD_FLAG" && "$(cat "$DOWNLOAD_FLAG")" == "1" ]]; then
        echo "$MODEL is currently being installed..."
        exit 0
    else
        # Start new download
        echo 1 > "$DOWNLOAD_FLAG"
        NOTIFICATION_ID=$(notify-send -a "AI Chat" -i "$AI_ICON_PATH" "Downloading $MODEL_NAME" "The app will open once the download is complete" --print-id)
    fi
    
    # Temp file to capture full Ollama pull output
    TMP_LOG=$(mktemp)
    
    # Check for connectivity to Ollama's model registry
    if ! curl --connect-timeout 3 -I https://ollama.com 2>&1; then
      notify-send --replace-id="$NOTIFICATION_ID" \
          -a "AI Chat" \
          -i "$AI_ICON_PATH" \
          "No Internet Connection" "Cannot download $MODEL_NAME\nCheck your connection and try again"
      exit 1
    fi
    
    echo "Downloading $MODEL_NAME ..."
    last_percent=""
    ollama pull "$MODEL" 2>&1 | tee "$TMP_LOG" | while read -r line; do
        if [[ $line =~ ([0-9]{1,3})% ]]; then
            percent="''${BASH_REMATCH[1]}"
            # Skip updating same percentage
            [[ "$percent" == "$last_percent" ]] && continue
            last_percent="$percent"
            NOTIFICATION_ID=$(notify-send --print-id --replace-id="$NOTIFICATION_ID" \
                -u critical \
                -h int:value:"$percent" \
                -a "AI Chat" \
                -i "$AI_ICON_PATH" \
                "Downloading $MODEL_NAME  $percent%" \
                "The app will open once the download is complete")
        fi
    done
    
    status=''${PIPESTATUS[0]}
    
    # Final notification
    if [[ $status -eq 0 ]]; then
        echo "Download completed successfully"
        notify-send --replace-id="$NOTIFICATION_ID" \
            -a "AI Chat" \
            -i "$AI_ICON_PATH" \
            "Download complete" \
            "The application will now open"
        alpaca --model "$MODEL"
        exit 0
    else
        echo "Download failed with status $status"
        error_msg=$(tail -n 1 "$TMP_LOG")
        notify-send --replace-id="$NOTIFICATION_ID" \
            -a "AI Chat" \
            -i "$AI_ICON_PATH" \
            "Failed to download $MODEL_NAME" \
            "Error occurred:\n''${error_msg}"
    fi
  '';

  meta = {
    description = "Script to setup and/or launch various free LLM models with Alpaca chat";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
