#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
exec swift "$@" --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
