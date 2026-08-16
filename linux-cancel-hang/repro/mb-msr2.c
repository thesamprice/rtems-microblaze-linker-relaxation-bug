/*
 * mb-msr2: does a signal handler modifying the interrupted MSR via ucontext take
 * effect on resume?  Other arches round-trip the status register through the
 * signal frame, so a handler can adjust the resumed arithmetic flags; MicroBlaze
 * setup/restore_sigcontext currently drop MSR entirely, so the change is lost.
 *
 * Main forces carry=0, opens a window; a fast SIGUSR1/SIGALRM storm lands a
 * handler in it that sets MSR_C in uc->uc_mcontext.regs.msr; main reads carry
 * back.  "propagated" counts in-window hits where carry came back SET -> the
 * ucontext MSR write reached the resumed context.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <signal.h>
#include <pthread.h>
#include <time.h>
#include <ucontext.h>

#define MSR_C 0x4u

static volatile int stop, sigs, hits, propagated, window;
static pthread_t main_tid;

static void handler(int s, siginfo_t *si, void *uc_v)
{
	(void)s; (void)si;
	ucontext_t *uc = uc_v;
	sigs++;
	uc->uc_mcontext.regs.msr |= MSR_C;   /* request carry set on resume */
	if (window) window = 2;              /* mark: landed while window open */
}

static void *spam(void *a){ (void)a; while(!stop) pthread_kill(main_tid, SIGUSR1); return 0; }

int main(void)
{
	struct sigaction sa = { .sa_sigaction = handler, .sa_flags = SA_SIGINFO | SA_RESTART };
	sigemptyset(&sa.sa_mask);
	sigaction(SIGUSR1, &sa, NULL);
	sigaction(SIGALRM, &sa, NULL);
	main_tid = pthread_self();
	pthread_t th; pthread_create(&th, NULL, spam, NULL);
	timer_t tid;
	struct sigevent sev = { .sigev_notify = SIGEV_SIGNAL, .sigev_signo = SIGALRM };
	timer_create(CLOCK_MONOTONIC, &sev, &tid);
	struct itimerspec its = { { 0, 60000 }, { 0, 60000 } };
	timer_settime(tid, 0, &its, NULL);

	printf("MSR2 START\n"); fflush(stdout);
	for (long i = 0; i < 6000 && hits < 200; i++) {
		unsigned long a, b;
		window = 1;
		asm volatile(
			"add r18, r0, r0\n\t"          /* force carry = 0 */
			"mfs %0, rmsr\n\t"             /* a */
			".rept 120000\n\t or r0,r0,r0\n\t .endr\n\t"
			"mfs %1, rmsr\n\t"             /* b */
			: "=r"(a), "=r"(b) :: "r18");
		int landed = (window == 2); window = 0;
		if (landed) { hits++; if ((b & MSR_C) && !(a & MSR_C)) propagated++; }
		if ((i & 0x1FF) == 0) {
			printf("MSR2 i=%ld sigs=%d hits=%d propagated=%d\n", i, sigs, hits, propagated);
			fflush(stdout);
		}
	}
	stop = 1; pthread_join(th, NULL);
	printf("MSR2 DONE hits=%d propagated=%d -> %s\n", hits, propagated,
	       propagated ? "ucontext MSR change PROPAGATED (msr round-trips)"
			  : "ucontext MSR change IGNORED (msr dropped from sigcontext)");
	fflush(stdout);
	return 0;
}
