/*
 * mayhem/harness/fuzz_bpfc.c — in-process libFuzzer driver for the new-bpf-tools compiler.
 *
 * Upstream's compiler (main.c) reads a C source program from STDIN, runs the whole front-end +
 * optimizer + code generator (preprocess -> tokenize -> parse -> optimize -> codegen -> print_code)
 * and writes assembly to STDOUT. The archived original Mayhem target only ran a *pre-compiled* test
 * program (`/a.out`) with NO input, so it never drove the compiler at all (0 edges). This driver feeds
 * the fuzzer's bytes through the EXACT same code path (compile_one_file -> run_core_tasks -> ... ->
 * run_codegen), so Mayhem/ASan/UBSan actually exercise the lexer, preprocessor, parser, optimizer and
 * amd64 code generator. It is a libFuzzer harness (Mayhem's first-class instrumented target form):
 * -fsanitize=fuzzer gives SanitizerCoverage edge feedback (a plain black-box file-input CLI records
 * ZERO edges under Mayhem's binary-only tracer — §6.2 item 11).
 *
 * Two upstream realities have to be bridged to run this compiler in-process, once per fuzz iteration:
 *
 *  1. INPUT comes from stdin (getchar()). Each iteration we point the global `stdin` FILE* at an
 *     in-memory stream over the fuzzer bytes (fmemopen) — no temp files, no absolute paths.
 *
 *  2. The compiler ABORTS the process with exit(1) on ANY rejected program (general.c fail(),
 *     diagnostics.c) and exit(0) on some modes — fine for a one-shot CLI, fatal for an in-process
 *     fuzzer (the first malformed input would kill the whole campaign). We interpose exit() via the
 *     linker (`-Wl,--wrap=exit`, see build.sh): while a compile is in flight, exit() longjmps back to
 *     the harness so a rejected program is just "input handled, next"; outside a compile (libFuzzer /
 *     ASan shutdown) it defers to the real exit so reporting still works. REAL faults use abort()
 *     (ASan/UBSan halting) or SIGSEGV, which are untouched — genuine defects still crash and are kept.
 *
 * main.c is compiled with -Dmain=bpf_original_main so its own main() is inert; we reuse its non-static
 * pipeline entry compile_one_file(). Emitted assembly is discarded (stdout -> /dev/null): we fuzz the
 * compiler, not the text of the asm. The compiler is a GC-less allocate-and-exit batch tool (tree.c:
 * "crazy mallocs ... no garbage collection"), so it leaks ~100KB/input — LSan is disabled in
 * asan_options.c (detect_leaks=0, sanctioned for allocate-and-exit tools); ASan+UBSan stay halting.
 * run_codegen() re-initializes every global codegen counter and both run_core_tasks() and setup use
 * fresh hash tables per call, so the pipeline is re-entrant across iterations.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <setjmp.h>

/* from tokens.c / tree.c — the same init main() performs before compiling */
extern void init_tokens(void);
extern void init_tree(void);
/* from main.c — the full read/preprocess/tokenize/parse/optimize/codegen pipeline */
extern void compile_one_file(void);
/* from main.c — used by diagnostics */
extern char *current_file;

/* exit() interposition (build.sh links with -Wl,--wrap=exit). __real_exit is the genuine libc exit. */
extern void __real_exit(int status) __attribute__((noreturn));

static jmp_buf g_exit_jmp;
static int g_in_compile = 0;

void __wrap_exit(int status)
{
	if (g_in_compile)
		longjmp(g_exit_jmp, status ? status : 256);   /* compiler rejected/finished this input */
	__real_exit(status);                                  /* libFuzzer / ASan shutdown — real exit */
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	static int inited = 0;
	if (!inited) {
		/* Discard the emitted assembly; we fuzz the compiler, not stdout text. */
		if (!freopen("/dev/null", "w", stdout)) { /* keep going even if /dev/null is unavailable */ }
		init_tokens();
		init_tree();
		inited = 1;
	}

	FILE *in = fmemopen((void *)data, size, "r");
	if (!in)
		return 0;
	stdin = in;                 /* the compiler reads its program via getchar()/stdin */
	current_file = "<stdin>";

	g_in_compile = 1;
	if (setjmp(g_exit_jmp) == 0)
		compile_one_file();     /* preprocess -> tokenize -> parse -> optimize -> amd64 codegen */
	g_in_compile = 0;

	fclose(in);
	return 0;
}
