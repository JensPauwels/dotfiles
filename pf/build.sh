#!/bin/sh
# Build the pf TUI next to the pf script. Needs Go.
set -e
cd "$(dirname "$0")/tui"
go build -trimpath -ldflags="-s -w" -o ../.local/bin/pf-tui .
echo "built $(cd .. && pwd)/.local/bin/pf-tui"
