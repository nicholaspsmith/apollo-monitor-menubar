#!/bin/bash
# Build Apollo Monitor.app via the shared StatusItemKit bundler.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ../StatusItemKit/scripts/make-app.sh ApolloMonitor "Apollo Monitor"
