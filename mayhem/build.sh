#!/usr/bin/env bash
#
# mayhem/build.sh — build new-bpf-tools' compiler fuzz target + functional oracle.
#
# new-bpf-tools (bl0ckeduser) is a from-scratch C-subset compiler: it reads a C program on stdin
# and emits assembly on stdout (preprocess -> tokenize -> parse -> optimize -> codegen). We build
# the amd64 code-generation configuration (codegen_amd64.c, upstream's build-amd64.sh path — the one
# whose test suite runs natively on this x86-64 base with no 32-bit multilib):
#
#   /mayhem/compile-bpfc   libFuzzer + sanitized + DWARF -> the Mayhem target. An in-process driver
#                          (mayhem/harness/fuzz_bpfc.c) that feeds each fuzzer input through the SAME
#                          compile_one_file() pipeline the compiler uses, so ASan/UBSan see bugs in
#                          the lexer/preprocessor/parser/optimizer/codegen. This replaces the archived
#                          original target, which only ran a *precompiled* test program (`/a.out`) with
#                          no input and so never fuzzed the compiler (0 edges). Built with
#                          $LIB_FUZZING_ENGINE (-fsanitize=fuzzer → SanitizerCoverage edge feedback):
#                          a plain black-box file-input CLI records ZERO edges under Mayhem's binary-only
#                          tracer (§6.2 item 11), so the target is CONVERTED to an in-process libFuzzer
#                          harness over the same code path (PORTING.md field note). The compiler aborts
#                          with exit() on rejected programs, so the harness is linked with
#                          `-Wl,--wrap=exit` and longjmps back per input (see fuzz_bpfc.c).
#   /mayhem/compile-bpfc-standalone  sanitized + DWARF (NO fuzzer) -> a run-once reproducer for triage:
#                          the same harness linked against $STANDALONE_FUZZ_MAIN (LLVM's run-once driver
#                          from the base) — takes one input file, runs LLVMFuzzerTestOneInput once,
#                          crashes naturally under gdb with no libFuzzer runtime in the way.
#   compiler/a.out         normal flags       -> the mayhem/test.sh oracle (upstream's own
#                          autotest-amd64.sh compares this compiler's output against cc across the
#                          full test/amd64 program suite).
#
# No network, no upstream edits (the driver + main() rename are additive, under mayhem/).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS COVERAGE_FLAGS

cd "${SRC:-/mayhem}/compiler"

# The compiler's translation units (upstream's build-amd64.sh source list, minus main.c which is
# handled specially per build). codegen_amd64.c + -DTARGET_AMD64 selects the amd64 backend.
CORE="codegen_amd64.c diagnostics.c general.c optimize.c parser.c tokenizer.c tokens.c \
tree.c typeof.c escapes.c hashtable.c preprocess.c constfold.c global_initializer.c"

# main.c is reused for its pipeline (run_core_tasks/compile_one_file); its own main() is renamed inert
# via -Dmain (applied to main.c ONLY, compiled to its own object, so the rename doesn't clobber the
# harness's main) and the harness (fuzz_bpfc.c) provides the real main(). The whole compiler is built
# with $SANITIZER_FLAGS so the fuzzed code — not just the driver — is instrumented; $DEBUG_FLAGS after
# it so -gdwarf-3 wins (DWARF < 4 for Mayhem triage). -w silences the 2012-era warnings; the compiler
# defines are guarded by TARGET_AMD64.
CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -DTARGET_AMD64 -std=gnu99 -w"
HARNESS="${SRC:-/mayhem}/mayhem/harness/fuzz_bpfc.c ${SRC:-/mayhem}/mayhem/harness/asan_options.c"
# The harness interposes the compiler's exit() (it aborts the process on every rejected program) so it
# can longjmp back and keep fuzzing in-process — link both binaries with the wrap so exit() -> __wrap_exit.
WRAP_EXIT="-Wl,--wrap=exit"

# main.c is compiled once to its own object with its own main() renamed inert (-Dmain); the harness
# provides LLVMFuzzerTestOneInput(). Reused for both binaries below.
# shellcheck disable=SC2086
$CC $CFLAGS -Dmain=bpf_original_main -c main.c -o ./bpf_main_mayhem.o

# 1) libFuzzer fuzz target (the Mayhem target). $LIB_FUZZING_ENGINE == -fsanitize=fuzzer provides both
#    the fuzzing driver and SanitizerCoverage edge feedback; $SANITIZER_FLAGS/$DEBUG_FLAGS keep ASan+UBSan
#    halting and DWARF < 4.
# shellcheck disable=SC2086
$CC $CFLAGS $LIB_FUZZING_ENGINE $WRAP_EXIT $CORE ./bpf_main_mayhem.o $HARNESS -lm -o /mayhem/compile-bpfc

# 1b) Standalone reproducer (NO fuzzer engine) — same harness linked against the base's run-once LLVM
#     driver, so a saved crashing input replays/triages under gdb without the libFuzzer runtime.
# shellcheck disable=SC2086
$CC $CFLAGS "$STANDALONE_FUZZ_MAIN" $WRAP_EXIT $CORE ./bpf_main_mayhem.o $HARNESS -lm -o /mayhem/compile-bpfc-standalone

# 2) Clean oracle build (NO sanitizers) — upstream's normal amd64 compiler, left at compiler/a.out
#    exactly where autotest-amd64.sh / compile-run-amd64.sh expect it. $COVERAGE_FLAGS is empty by
#    default (no effect); set it to instrument the oracle for source-coverage measurement.
# shellcheck disable=SC2086
$CC -O0 -g -DTARGET_AMD64 -std=gnu99 -w $COVERAGE_FLAGS \
    $CORE main.c -lm -o ./a.out

echo "build.sh: built /mayhem/compile-bpfc (libFuzzer target), /mayhem/compile-bpfc-standalone (reproducer), compiler/a.out (oracle)"
