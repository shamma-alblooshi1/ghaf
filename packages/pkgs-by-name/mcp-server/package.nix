# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "mcp-server";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "ai-agents";
    repo = "mcp-server";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    # Note: Replace with actual hash once a real repository is available
  };

  vendorHash = null; # Set to null for first build

  meta = with lib; {
    description = "Message Control Protocol server for AI agents";
    homepage = "https://github.com/ai-agents/mcp-server";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    mainProgram = "mcp-server";
  };
}
