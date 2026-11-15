#!/bin/sh
# Build home into .local/bin, where stow links it from. Needs Go.
set -e
cd "$(dirname "$0")/src"
go build -trimpath -ldflags="-s -w" -o ../.local/bin/home .
echo "built $(cd .. && pwd)/.local/bin/home"
