# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib
, buildGoModule
}:

buildGoModule rec {
  pname = "mcp-server";
  version = "0.1.0";

  src = ./.;  # Use local directory as source

  vendorHash = null; # Set to null for first build

  meta = with lib; {
    description = "Message Control Protocol server for AI agents";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    mainProgram = "mcp-server";
  };
}
