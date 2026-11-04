#!/bin/bash
# Usage: tests/run_tests.sh <role> [seconds]
#   roles: practice | host | client | client_quit | host_quit
#   LAN test: run "host" in one terminal and "client" in another at the same time.
# Screenshots: tests/run_tests.sh shots   (needs xvfb-run; images go to /tmp/shots)
cd "$(dirname "$0")/.."
ROLE=${1:-practice}; SECS=${2:-120}
trap 'rm -f override.cfg' EXIT
if [ "$ROLE" = "shots" ]; then
  printf '[autoload]\n\nShots="*res://tests/screenshots.gd"\n' > override.cfg
  timeout "$SECS" xvfb-run -a godot --rendering-driver opengl3 --path . 2>&1
else
  printf '[autoload]\n\nTestRunner="*res://tests/test_runner.gd"\n' > override.cfg
  timeout "$SECS" godot --headless --path . -- --role="$ROLE" 2>&1
fi
