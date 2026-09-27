#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p docs/abi
forge inspect src/LaunchToken.sol:LaunchToken abi --json > docs/abi/LaunchToken.json
forge inspect src/GuildDues.sol:GuildDues abi --json > docs/abi/GuildDues.json
