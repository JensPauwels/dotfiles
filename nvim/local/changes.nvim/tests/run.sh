#!/bin/sh
# Run the test suite: tests/run.sh [substring-of-test-file]
cd "$(dirname "$0")/.." && TEST="$1" nvim --headless -u NONE -l tests/run.lua
