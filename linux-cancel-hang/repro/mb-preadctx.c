/* Does pread(pipe,off=0) behave differently by call context? Main thread vs a
 * pthread vs raw syscall.  The AIO helper (a glibc helper thread) gets EINVAL;
 * a direct pread gets ESPIPE.  Isolate where the EINVAL comes from. */
#define _GNU_SOURCE
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
static int pfd[2];
static void rep(const char*w,long r,int e){
	char m[160];int n=snprintf(m,sizeof m,"  %-22s ret=%ld errno=%d (%s)\n",w,r,e,strerror(e));
	write(2,m,n);
}
static void *thr(void*a){(void)a;
	char b[128];errno=0;long r=pread(pfd[0],b,sizeof b,0);int e=errno;
	rep("pread in pthread",r,e);return 0;
}
int main(void){
	char b[128];
	if(pipe(pfd)<0)return 2;
	errno=0;long r=pread(pfd[0],b,sizeof b,0);int e=errno; rep("pread in main",r,e);
	pthread_t t;pthread_create(&t,0,thr,0);pthread_join(t,0);
	/* raw pread64 syscall: microblaze is 32-bit; pass 64-bit off as lo,hi (0,0) */
	errno=0;
#ifdef SYS_pread64
	r=syscall(SYS_pread64,pfd[0],b,(unsigned)sizeof b,(long)0,(long)0);e=errno;
	rep("raw SYS_pread64 lo,hi",r,e);
#endif
	write(2,"PREADCTX END\n",13);
	return 0;
}
