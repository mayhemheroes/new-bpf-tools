#!/usr/bin/env bash
#
# mayhem/test.sh — functional oracle for new-bpf-tools. RUNS upstream's OWN test suite
# (compiler/autotest-amd64.sh) against the clean oracle compiler (compiler/a.out, built by
# mayhem/build.sh); it never compiles the compiler itself.
#
# UPSTREAM SUITE: autotest-amd64.sh is the project's real functional test suite. For every program
# under compiler/test/amd64/ (plus the std/ and multifile/ groups) it compiles the program with THIS
# compiler, assembles+links+runs the result, and compares its output (via `sum`) against the output
# of the same program built by the reference C compiler `cc`. A program "passes" only when
# new-bpf-tools reproduces cc's runtime behavior byte-for-byte — a genuine known-answer behavioral
# oracle, not an exit-code check. A patch that breaks codegen flips passes to fails; a compiler
# neutered to exit(0) emits empty assembly whose program output no longer matches cc, so every case
# fails (not reward-hackable). We run the amd64 configuration because it executes natively on this
# x86-64 base (no 32-bit multilib) and passes cleanly upstream.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC/compiler"

emit_ctrf() {
  local tool="$1" p="$2" f="$3" s="${4:-0}"; local tests=$(( p + f + s ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": { "tests": $tests, "passed": $p, "failed": $f, "pending": 0, "skipped": $s, "other": 0 }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":0,"skipped":%d,"other":0}}}\n' \
    "$tool" "$tests" "$p" "$f" "$s"
  [ "$f" -eq 0 ]
}

if [ ! -x ./a.out ]; then
  echo "test.sh: compiler/a.out missing — build.sh must build it (not rebuilding here)" >&2
  emit_ctrf new-bpf-tools 0 1; exit 1
fi

# The suite's reference compiler is hardcoded as `cc` (autotest-amd64.sh). The test programs are
# 2012-era K&R-ish C (implicit-int `main(){}`), which gcc-14 (debian trixie's cc, C23 default)
# rejects as an ERROR — breaking the REFERENCE builds, not this project. Shim `cc` on PATH to the
# real cc in -std=gnu89 mode (the dialect the suite was written for) so the reference side compiles,
# exactly as it did on the older systems upstream developed on. No upstream file is modified.
shim="$(mktemp -d)"
printf '#!/bin/sh\nexec /usr/bin/cc -std=gnu89 -w "$@"\n' > "$shim/cc"
chmod +x "$shim/cc"
export PATH="$shim:$PATH"

# Run upstream's suite; it prints each case as "<file> - PASS/FAIL" and a totals block at the end.
out="$(sh ./autotest-amd64.sh 2>/dev/null)"
echo "$out"

passed="$(printf '%s\n' "$out" | sed -n 's/^passes: \([0-9]\+\).*/\1/p' | tail -1)"
failed="$(printf '%s\n' "$out" | sed -n 's/^fails: \([0-9]\+\).*/\1/p' | tail -1)"
: "${passed:=0}"; : "${failed:=0}"

if [ "$(( passed + failed ))" -eq 0 ]; then
  echo "test.sh: autotest-amd64.sh produced no results — cannot run oracle" >&2
  emit_ctrf new-bpf-tools 0 1; exit 1
fi

# Canary (known-answer, not just A/B): the suite compares THIS compiler's output against the
# reference compiler's — if both sides are silently broken (e.g. every project binary neutered to
# exit(0)), two empty outputs compare equal and every case "passes". Pin one case to a hardcoded
# expected answer: fib.c must actually print the fibonacci sequence.
canary="$(./compile-run-amd64.sh test/amd64/fib.c 2>/dev/null)"
if printf '%s' "$canary" | grep -q '^55$'; then
  echo "canary (fib.c known-answer) - PASS"; passed=$(( passed + 1 ))
else
  echo "canary (fib.c known-answer) - FAIL (no fibonacci output)"; failed=$(( failed + 1 ))
fi

echo "test.sh: passed=$passed failed=$failed"
emit_ctrf new-bpf-tools "$passed" "$failed"
