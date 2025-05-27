# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib
, writeTextFile
, makeWrapper
, coreutils
, jq
, socat
, bash
}:

import ./mcp-server.nix {
  inherit lib writeTextFile makeWrapper coreutils jq socat bash;
}
