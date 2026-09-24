#!/usr/bin/env bash
# Runs the whole test suite with the pinned Xcode toolchain.
#
#   Scripts/test.sh                                  every test
#   Scripts/test.sh --filter CodometerSourceLintTests just the source lints
#
# Gated suites stay off unless their environment variable is set:
#   CODOMETER_SNAPSHOT_DIR=<dir>   write the -en and -ru renders of the snapshot suites there
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=lib/common.sh
source Scripts/lib/common.sh
resolve_developer_dir

swift test "$@"
