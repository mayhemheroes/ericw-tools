#!/usr/bin/env bash
#
# ericw-tools/mayhem/test.sh — RUN ericw-tools' own GoogleTest suite (the `tests` binary built by
# mayhem/build.sh with NORMAL flags) and emit a CTRF summary. exit 0 iff no test failed.
# PATCH-grade oracle: these are ericw-tools' real known-answer tests (BSP/qbsp/vis/light/maputil
# round-trips, golden compares, geometry invariants) — they assert BEHAVIOR, so a no-op "exit(0)"
# patch cannot pass. This script only RUNS the pre-built binary; it never compiles.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN=./build-tests/tests/tests
if [ ! -x "$BIN" ]; then
  echo "missing $BIN — run mayhem/build.sh first" >&2
  emit_ctrf "googletest" 0 1 0
  exit 2
fi

# The tests read maps from testmaps/ via an absolute path baked into testmaps.hh at configure time,
# so run from $SRC. Some benchmark cases need a writable cwd.
echo "=== running $BIN ==="
out="$("$BIN" 2>&1)"; echo "$out"

# GoogleTest summary lines: "[==========] N tests from M test suites ran." / "[  PASSED  ] P" /
# "[  SKIPPED ] S". failed = total - passed - skipped (robust against repeated FAILED lines).
TOTAL=$( printf '%s\n' "$out" | sed -n 's/.*\[=*\] \([0-9][0-9]*\) tests* from .*ran\..*/\1/p' | tail -1)
PASSED=$( printf '%s\n' "$out" | sed -n 's/.*\[ *PASSED *\] \([0-9][0-9]*\) tests*\..*/\1/p'     | tail -1)
SKIPPED=$(printf '%s\n' "$out" | sed -n 's/.*\[ *SKIPPED *\] \([0-9][0-9]*\) tests*,*.*/\1/p'    | tail -1)
: "${TOTAL:=0}" "${PASSED:=0}" "${SKIPPED:=0}"

if [ "$TOTAL" -eq 0 ]; then
  echo "no GoogleTest summary parsed from $BIN output" >&2
  emit_ctrf "googletest" 0 1 0
  exit 2
fi

FAILED=$(( TOTAL - PASSED - SKIPPED )); [ "$FAILED" -lt 0 ] && FAILED=0
emit_ctrf "googletest" "$PASSED" "$FAILED" "$SKIPPED"
