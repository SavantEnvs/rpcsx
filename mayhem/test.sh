#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer tests for the code the fuzz targets reach (upstream ships no
# unit tests). Runs the drivers mayhem/build.sh built with normal flags and diffs their output
# against committed golden files:
#   psf_roundtrip  psf::load + psf::save_object on a PARAM.SFO   -> mayhem/tests/psf/game.expected
#   iso_tree       iso_dev directory walk + file reads on an ISO  -> mayhem/tests/iso_joliet.expected
#   pup_valid / pup_hash_mismatch  pup_object header/table parse + HMAC check -> mayhem/tests/pup/*.expected
#   unself_elf     tools/unself SELF -> ELF conversion            -> mayhem/tests/unself/expected.elf
#                  (expected bytes computed independently by mayhem/tools/gen_seeds.py)
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
: "${SRC:=/mayhem}"
cd "$SRC"

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

BIN="$SRC/mayhem/out/test"
T="$SRC/mayhem/tests"
for b in psf_dump iso_dump pup_dump unself; do
  [ -x "$BIN/$b" ] || { echo "missing $BIN/$b — run mayhem/build.sh first" >&2; emit_ctrf "rpcsx-known-answer" 0 5; exit 1; }
done
scratch=$(mktemp -d "${TMPDIR:-/tmp}/rpcsx-test.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

passed=0 failed=0
check() {  # check <name> <expected file> <actual file>
  if cmp -s "$2" "$3"; then echo "PASS $1"; passed=$((passed + 1));
  else echo "FAIL $1"; diff <(od -c "$2" | head -40) <(od -c "$3" | head -40) | head -20; failed=$((failed + 1)); fi
}

"$BIN/psf_dump" "$T/psf/game.sfo" > "$scratch/psf.out" 2>/dev/null
check psf_roundtrip "$T/psf/game.expected" "$scratch/psf.out"

"$BIN/iso_dump" "$T/iso/joliet.iso" > "$scratch/iso.out" 2>/dev/null
check iso_tree "$T/iso_joliet.expected" "$scratch/iso.out"

"$BIN/pup_dump" "$T/pup/fw.pup" > "$scratch/pup.out" 2>/dev/null
check pup_valid "$T/pup/fw.expected" "$scratch/pup.out"

"$BIN/pup_dump" "$T/pup/tampered.pup" > "$scratch/pup_bad.out" 2>/dev/null
check pup_hash_mismatch "$T/pup/tampered.expected" "$scratch/pup_bad.out"

rm -f "$scratch/out.elf"
"$BIN/unself" "$T/unself/sample.self" "$scratch/out.elf" 2>/dev/null
touch "$scratch/out.elf"
check unself_elf "$T/unself/expected.elf" "$scratch/out.elf"

emit_ctrf "rpcsx-known-answer" "$passed" "$failed"
