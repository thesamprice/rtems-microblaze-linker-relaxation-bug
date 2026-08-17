/*
 * mb-eintr: reproduce Ramin's tst-eintr1 segfault signature on MicroBlaze.
 *
 * The kernel bug: ret_from_trap unconditionally stores r3/r4 into pt_regs on
 * the rt_sigreturn path, clobbering the r4 that restore_sigcontext just set.
 * It only bites when a signal lands inside a window that keeps a live ADDRESS
 * in r4 -- exactly the lwx/swx CAS retry loops gcc emits for __sync/__atomic.
 * On the bad sigreturn r4 becomes 0, the CAS then dereferences address 0 and
 * the process dies with SIGSEGV (fault at 0, r4=0).
 *
 * Recipe (per Ramin): worker threads hammer __sync_val_compare_and_swap on a
 * heap counter (address stays in r4 across the retry loop) while a SIGUSR1
 * storm is delivered across them. Each trial runs in a child; count how many
 * of N children die by SIGSEGV. A/B: unpatched kernel > 0, patched kernel = 0.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/wait.h>

#define NWORK 4
#define TRIALS 40
#define SPIN 2000000

static volatile int stop;
static void h(int s){ (void)s; }

static void *worker(void *arg)
{
	unsigned *ctr = arg;               /* heap address -> lives in r4 in the CAS loop */
	for (long i = 0; i < SPIN && !stop; i++) {
		unsigned old = __atomic_load_n(ctr, __ATOMIC_RELAXED);
		__sync_val_compare_and_swap(ctr, old, old + 1);
	}
	return NULL;
}

/* one trial: fork a child that runs the CAS + signal storm; return its status */
static int trial(void)
{
	pid_t p = fork();
	if (p == 0) {
		struct sigaction sa = { .sa_handler = h, .sa_flags = SA_RESTART };
		sigemptyset(&sa.sa_mask);
		sigaction(SIGUSR1, &sa, NULL);
		unsigned *ctr = malloc(sizeof *ctr);
		*ctr = 0;
		pthread_t th[NWORK];
		for (int i = 0; i < NWORK; i++)
			pthread_create(&th[i], NULL, worker, ctr);
		/* signal storm across the workers while they spin in the CAS loop */
		for (int r = 0; r < 4000; r++)
			for (int i = 0; i < NWORK; i++)
				pthread_kill(th[i], SIGUSR1);
		stop = 1;
		for (int i = 0; i < NWORK; i++)
			pthread_join(th[i], NULL);
		_exit(0);
	}
	int st; waitpid(p, &st, 0);
	return st;
}

int main(void)
{
	int segv = 0, other = 0, ok = 0;
	printf("EINTR-TEST START (%d trials)\n", TRIALS); fflush(stdout);
	for (int t = 0; t < TRIALS; t++) {
		int st = trial();
		if (WIFSIGNALED(st)) {
			if (WTERMSIG(st) == SIGSEGV) segv++;
			else other++;
		} else ok++;
		if ((t % 8) == 0) { printf("EINTR-TEST t=%d segv=%d other=%d ok=%d\n", t, segv, other, ok); fflush(stdout); }
	}
	printf("EINTR-TEST DONE trials=%d segv=%d other=%d ok=%d -> %s\n",
	       TRIALS, segv, other, ok,
	       segv ? "SIGSEGV reproduced (ret_from_trap r4-clobber bug present)"
		    : "no segfaults (r4 preserved)");
	fflush(stdout);
	return segv ? 1 : 0;
}
