#!/bin/bash
#
# Unit tests for test/install-test-comment: verifies colored regression and
# improvement formatting at each row's threshold, quiet rendering within noise,
# missing baselines, and per-phase deltas.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/test/install-test-comment"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

make_art() {
  local dir=$1 build=$2 inst=$3 fb=$4 eb=$5 p1=$6 p2=$7
  mkdir -p "$dir/runs/20261128-120000-boot"
  echo "success" >"$dir/status"
  echo "$build" >"$dir/build-seconds"
  cat >"$dir/omarchy-install-timing.json" <<JSON
{"started_at": 0, "finished_at": $inst, "phases": [
  {"name": "Installing Arch + Omarchy", "elapsed": $p1},
  {"name": "Finalizing boot and user", "elapsed": $p2}
]}
JSON
  echo "Startup finished in 1.0s (firmware) + 1.0s (loader) + 1.0s (kernel) + ${fb}s (userspace) = 5.0s" \
    >"$dir/first-boot-systemd-analyze.txt"
  echo "Startup finished in 1.0s (firmware) + 1.0s (loader) + 1.0s (kernel) + ${eb}s (userspace) = 5.0s" \
    >"$dir/runs/20261128-120000-boot/systemd-analyze.txt"
}

mkdir -p "$work/pr" "$work/base"
# x86_64: Build +12.0s (red), Install +7.4s (red), First boot +0.1s (neutral), Everyday boot -0.6s (green)
# aarch64: Build -11.0s (green), Install -1.7s (green), First boot +0.5s (red), Everyday boot +0.0s (neutral)
make_art "$work/base/install-test-1-1-x86_64" 70.0 13.4 3.8 3.8 3.7 0.3
make_art "$work/pr/install-test-2-1-x86_64"   82.0 20.8 3.9 3.2 4.1 7.4
make_art "$work/base/install-test-1-1-aarch64" 174.0 28.7 4.0 3.9 5.0 12.2
make_art "$work/pr/install-test-2-1-aarch64"   163.0 27.0 4.5 3.9 4.2 12.1

out=$("$SCRIPT" "$work/pr" "$work/base" success "https://example.invalid/run/2" "abcdef1234567890")

grep -Fq "| Build the ISO | 82.0 s | 🔴 **+12.0 s** | 163.0 s | 🟢 −11.0 s |" <<<"$out" || fail "Build row mismatch:\n$out"
grep -Fq "| Install | 20.8 s | 🔴 **+7.4 s** | 27.0 s | 🟢 −1.7 s |" <<<"$out" || fail "Install row mismatch:\n$out"
grep -Fq "| First boot | 5.9 s | +0.1 s | 6.5 s | 🔴 **+0.5 s** |" <<<"$out" || fail "First boot row mismatch:\n$out"
grep -Fq "| Everyday boot | 5.2 s | 🟢 −0.6 s | 5.9 s | +0.0 s |" <<<"$out" || fail "Everyday boot row mismatch:\n$out"
pass "summary table highlights regressions in red, wins in green, and leaves noise plain"

grep -Fq "| Phase | This PR | quattro | vs quattro |" <<<"$out" || fail "phase header missing vs quattro:\n$out"
grep -Fq "| Installing Arch + Omarchy | 4.1 s | 3.7 s | +0.4 s |" <<<"$out" || fail "neutral phase delta mismatch:\n$out"
grep -Fq "| Finalizing boot and user | 7.4 s | 0.3 s | 🔴 **+7.1 s** |" <<<"$out" || fail "red phase delta mismatch:\n$out"
grep -Fq "| Installing Arch + Omarchy | 4.2 s | 5.0 s | 🟢 −0.8 s |" <<<"$out" || fail "green phase delta mismatch:\n$out"
pass "phase breakdown colors >= 0.5 s regressions/improvements and keeps smaller deltas plain"

# Missing baseline renders en-dashes cleanly without color markers.
mkdir -p "$work/empty-base"
out_nobase=$("$SCRIPT" "$work/pr" "$work/empty-base" success "https://example.invalid/run/2" "abcdef1234567890")
grep -Fq "| Install | 20.8 s | – | 27.0 s | – |" <<<"$out_nobase" || fail "missing baseline mismatch:\n$out_nobase"
grep -Fq "| Finalizing boot and user | 7.4 s | – | – |" <<<"$out_nobase" || fail "missing phase baseline mismatch:\n$out_nobase"
pass "missing baseline renders en-dashes cleanly"

# Rounding boundary: 1.00 - 0.55 = 0.45 rounds half-away-from-zero to +0.5 s in
# BOTH the summary table and the phase breakdown, coloring both consistently.
mkdir -p "$work/b-base" "$work/b-pr"
make_art "$work/b-base/install-test-1-1-x86_64" 70.0 13.0 0.55 0.55 0.55 0.55
make_art "$work/b-pr/install-test-2-1-x86_64"   70.0 13.0 1.00 1.00 1.00 1.00
out_b=$("$SCRIPT" "$work/b-pr" "$work/b-base" success "https://example.invalid/run/3" "1234567890abcdef")
grep -Fq "| First boot | 3.0 s | 🔴 **+0.5 s** |" <<<"$out_b" || fail "summary boundary rounding mismatch:
$out_b"
grep -Fq "| Installing Arch + Omarchy | 1.0 s | 0.6 s | 🔴 **+0.5 s** |" <<<"$out_b" || fail "phase boundary rounding mismatch:
$out_b"
pass "summary and phase tables share half-away-from-zero rounding at 0.45 boundary"

# Exact millisecond cutoffs: 3.050 - 2.600 = +0.450 -> +0.5 s (red), reversed ->
# -0.5 s (green), and 0.06 - 0.01 = +0.05 -> +0.1 s consistently in both tables.
mkdir -p "$work/c-base" "$work/c-pr"
make_art "$work/c-base/install-test-1-1-x86_64" 70.0 13.0 0.600 1.050 2.600 0.010
make_art "$work/c-pr/install-test-2-1-x86_64"   70.0 13.0 1.050 0.600 3.050 0.060
out_c=$("$SCRIPT" "$work/c-pr" "$work/c-base" success "https://example.invalid/run/4" "abcdef1234567890")
grep -Fq "| First boot | 3.1 s | 🔴 **+0.5 s** |" <<<"$out_c" || fail "3.050 vs 2.600 summary mismatch:\n$out_c"
grep -Fq "| Everyday boot | 2.6 s | 🟢 −0.5 s |" <<<"$out_c" || fail "2.600 vs 3.050 summary mismatch:\n$out_c"
grep -Fq "| Installing Arch + Omarchy | 3.1 s | 2.6 s | 🔴 **+0.5 s** |" <<<"$out_c" || fail "3.050 vs 2.600 phase mismatch:\n$out_c"
grep -Fq "| Finalizing boot and user | 0.1 s | 0.0 s | +0.1 s |" <<<"$out_c" || fail "0.06 vs 0.01 phase mismatch:\n$out_c"
pass "exact millisecond rounding matches in summary and phase tables across all cutoffs"

# Sub-millisecond precision is preserved before rounding to tenths, empty
# sanitized phase names do not shift columns, and malformed JSON exits non-zero.
mkdir -p "$work/d-base/install-test-1-1-x86_64" "$work/d-pr/install-test-2-1-x86_64"
echo "success" >"$work/d-pr/install-test-2-1-x86_64/status"
cat >"$work/d-base/install-test-1-1-x86_64/omarchy-install-timing.json" <<'JSON'
{"started_at": 1700000000.0, "finished_at": 1700000070.0, "phases": [
  {"name": "Sub-ms check", "elapsed": 2.6004},
  {"name": "!!!", "elapsed": 1.0}
]}
JSON
cat >"$work/d-pr/install-test-2-1-x86_64/omarchy-install-timing.json" <<'JSON'
{"started_at": 1700000000.4, "finished_at": 1700000071.35, "phases": [
  {"name": "Sub-ms check", "elapsed": 3.050},
  {"name": "Cell check", "elapsed": 3.0499},
  {"name": "!!!", "elapsed": 1.2}
]}
JSON
out_d=$("$SCRIPT" "$work/d-pr" "$work/d-base" success "https://example.invalid/run/5" "abcdef1234567890")
grep -Fq "| Install | 71.0 s | 🔴 **+1.0 s** |" <<<"$out_d" || fail "epoch timestamp exact +0.95 s install cutoff mismatch:\n$out_d"
grep -Fq "| Sub-ms check | 3.1 s | 2.6 s | +0.4 s |" <<<"$out_d" || fail "sub-ms delta mismatch:\n$out_d"
grep -Fq "| Cell check | 3.0 s | – | – |" <<<"$out_d" || fail "sub-ms cell mismatch:\n$out_d"
grep -Fq "|  | 1.2 s | 1.0 s | +0.2 s |" <<<"$out_d" || fail "empty sanitized phase name shifted columns:\n$out_d"
echo "{bad json" >"$work/d-pr/install-test-2-1-x86_64/omarchy-install-timing.json"
if "$SCRIPT" "$work/d-pr" "$work/d-base" success "https://example.invalid/run/5" "abcdef1234567890" >/dev/null 2>&1; then
  fail "malformed timing JSON must exit non-zero"
fi
pass "exact decimal rounding, empty sanitized phase names, and malformed JSON handling pass"

# Non-numeric / multiline string elapsed values must be rejected so they can
# never split lines or bypass the Markdown phase-name sanitizer.
cat >"$work/d-pr/install-test-2-1-x86_64/omarchy-install-timing.json" <<'JSON'
{"started_at": 1700000000.0, "finished_at": 1700000010.0, "phases": [
  {"name": "Phase", "elapsed": "1.0\n| Injected | 0.0 s |"}
]}
JSON
if "$SCRIPT" "$work/d-pr" "$work/d-base" success "https://example.invalid/run/5" "abcdef1234567890" >/dev/null 2>&1; then
  fail "multiline string elapsed value must exit non-zero"
fi
pass "rejects non-numeric and multiline string elapsed values"

# Zero-byte timing files (left behind when SSH timing collection fails) must be
# treated as missing so the workflow still posts the comment.
mkdir -p "$work/e-base/install-test-1-1-x86_64" "$work/e-pr/install-test-2-1-x86_64"
echo "success" >"$work/e-pr/install-test-2-1-x86_64/status"
: >"$work/e-base/install-test-1-1-x86_64/omarchy-install-timing.json"
: >"$work/e-pr/install-test-2-1-x86_64/omarchy-install-timing.json"
out_e=$("$SCRIPT" "$work/e-pr" "$work/e-base" success "https://example.invalid/run/6" "abcdef1234567890")
grep -Fq "| Install | – | – |" <<<"$out_e" || fail "zero-byte timing JSON broke summary:\n$out_e"
grep -Fq "[Run](https://example.invalid/run/6) · abcdef12" <<<"$out_e" || fail "zero-byte timing JSON dropped footer:\n$out_e"
if grep -Fq "<details>" <<<"$out_e"; then
  fail "zero-byte timing JSON should omit phase table:\n$out_e"
fi
# Zero-byte baseline timing JSON with valid PR timing JSON still renders phases with en-dashes.
cat >"$work/e-pr/install-test-2-1-x86_64/omarchy-install-timing.json" <<'JSON'
{"started_at": 1700000000.0, "finished_at": 1700000010.0, "phases": [{"name": "Phase A", "elapsed": 2.0}]}
JSON
out_e2=$("$SCRIPT" "$work/e-pr" "$work/e-base" success "https://example.invalid/run/6" "abcdef1234567890")
grep -Fq "| Phase A | 2.0 s | – | – |" <<<"$out_e2" || fail "zero-byte baseline timing JSON broke phase row:\n$out_e2"
pass "treats zero-byte timing JSON files as missing while keeping full comment output"
