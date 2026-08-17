/* Replicate glibc's AIO helper read path (rt/aio_misc.c handle_fildes_io)
 * exactly, on a pipe, WITHOUT aio: pread -> if ESPIPE -> read.
 * An alarm(3) tells us whether the fallback read() blocks (expected: the
 * request stays pending, aio_suspend blocks, cancel works) or returns
 * an error immediately (which would explain aio_error=EINVAL). */
#define _GNU_SOURCE
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
static void say(const char*s){write(2,s,strlen(s));}
static volatile int fired=0;
static void onalrm(int s){(void)s;fired=1;say("  [alarm] read() is BLOCKING (good)\n");}
int main(void){
	int pfd[2]; char buf[128]; char m[160]; int n;
	if(pipe(pfd)<0)return 2;
	/* step 1: pread like the helper */
	errno=0; ssize_t r=pread(pfd[0],buf,sizeof buf,0); int e=errno;
	n=snprintf(m,sizeof m,"pread    ret=%ld errno=%d (%s)\n",(long)r,e,strerror(e));write(2,m,n);
	if(r==-1&&e==ESPIPE){
		say("  -> ESPIPE, doing fallback read() (helper path)\n");
		signal(SIGALRM,onalrm); alarm(3);
		errno=0; r=read(pfd[0],buf,sizeof buf); e=errno;
		n=snprintf(m,sizeof m,"read     ret=%ld errno=%d (%s) blocked=%d\n",
			(long)r,e,strerror(e),fired);write(2,m,n);
	}
	say("AIOHELPER DONE\n");
	return 0;
}
