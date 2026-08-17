/* Minimal reproducer for tst-cancel17: cancel a thread blocked in aio_suspend()
 * (waiting on an aio_read of an empty pipe).  Prints exactly what happens:
 * whether the thread cancels (cleanup runs) or aio_suspend returns (bug), with
 * the return value/errno. */
#define _GNU_SOURCE
#include <aio.h>
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

static int pfd[2];
static struct aiocb a;
static const struct aiocb *l[1];

static void say(const char *s){ write(2, s, strlen(s)); }
static void cl(void *arg){ (void)arg; say("  cleanup ran -> thread CANCELLED (good)\n"); }

static void *tf(void *arg)
{
	(void)arg;
	int r, e;
	say("  tf: entering aio_suspend\n");
	pthread_cleanup_push(cl, NULL);
	errno = 0;
	r = aio_suspend(l, 1, NULL);
	e = errno;
	pthread_cleanup_pop(0);
	int ae = aio_error(&a);
	ssize_t ar = aio_return(&a);
	char m[128]; int n = snprintf(m, sizeof m,
		"  tf: aio_suspend r=%d errno=%d | aio_error=%d (%s) aio_return=%ld\n",
		r, e, ae, ae == 0 ? "done" : strerror(ae), (long)ar);
	write(2, m, n);
	return NULL;
}

int main(void)
{
	if (pipe(pfd) < 0) return 2;
	static char buf[128];
	memset(&a, 0, sizeof a);
	a.aio_fildes = pfd[0];
	a.aio_buf = buf;
	a.aio_nbytes = sizeof buf;   /* blocks: empty pipe, write end open */
	l[0] = &a;
	if (aio_read(&a) != 0) { say("aio_read failed\n"); return 2; }
	pthread_t th;
	pthread_create(&th, NULL, tf, NULL);
	sleep(1);
	say("main: pthread_cancel\n");
	pthread_cancel(th);
	void *ret;
	pthread_join(th, &ret);
	say(ret == PTHREAD_CANCELED ? "main: JOINED, CANCELED (PASS)\n"
				    : "main: JOINED, not canceled\n");
	say("AIOSUSP DONE\n");
	return 0;
}
