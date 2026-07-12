/*
 * Disable LeakSanitizer ONLY (ASan + UBSan stay on and halting).
 *
 * Justified twice over for this target:
 *  - the compiler is a classic allocate-and-exit batch tool: it builds tokens/AST/codegen state
 *    for ONE compilation and exits without freeing (my_strdup/malloc everywhere, no free) — LSan
 *    reports ~100KB of "leaks" on EVERY valid input, which would flood Mayhem with false defects;
 *  - LSan's end-of-process ptrace attach conflicts with Mayhem's own ptrace-based coverage
 *    collection (one tracer per process), turning every run into a 0-edge "Run Failed"
 *    (README.md FAQ, cause 1).
 */
/* STRONG symbols (not weak): with clang-19's static ASan runtime the weak form loses to the
 * runtime's own weak default and LSan stays on — a strong definition always wins (README.md). */
const char *__asan_default_options(void) { return "detect_leaks=0"; }
const char *__lsan_default_options(void) { return ""; }
int __lsan_is_turned_off(void) { return 1; }
