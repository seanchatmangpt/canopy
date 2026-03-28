#!/bin/sh
set -euo pipefail
cd /app
./bin/canopy eval "Canopy.Release.migrate"
exec ./bin/canopy start
