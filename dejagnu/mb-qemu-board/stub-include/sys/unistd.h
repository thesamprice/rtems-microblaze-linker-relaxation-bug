/* Just enough <sys/unistd.h> for DejaGnu's testglue.c, which includes it to
   declare write().  See ../README for why these stubs exist at all. */
#ifndef _MB_SYS_UNISTD_H
#define _MB_SYS_UNISTD_H
typedef unsigned long _mb_size_t;
int write (int, const void *, _mb_size_t);
int read (int, void *, _mb_size_t);
#endif
