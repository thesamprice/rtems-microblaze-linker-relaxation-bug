/* Everything RTEMS's newlib needs to run on bare metal.

   The RTEMS toolchain's newlib expects RTEMS to supply three things it does
   not have here: the per-thread reentrancy pointer, the mutex primitives its
   stdio locks against, and malloc.  Single-threaded on one core, the first is
   one static struct, the second is a pair of no-ops, and the third is a bump
   allocator over _sbrk.  The rest is the usual reentrant syscall layer.

   Using RTEMS's own newlib rather than a separate bare-metal libc is
   deliberate: it means the testsuite exercises the C library RTEMS actually
   ships, and printf, malloc and friends behave as they will in a real
   application.

   The only device touched is the UART-lite at 0x84000000 -- TX at +4, status
   at +8, TX-full is bit 3 -- which stock upstream QEMU's
   petalogix-s3adsp1800 provides.  Nothing else is needed: DejaGnu's own
   testglue.c prints "*** EXIT code N" through write(), and mb-qemu-run stops
   QEMU from outside once it appears.  All this file owes the protocol is a
   working write(1, ...) and an exit() that does not return.

   With MB_NO_LIBC this instead provides a tiny freestanding runtime and
   includes no headers at all, for a toolchain that has libgcc but no C
   library -- an uninstalled trunk cross build, for instance.  Tests wanting
   real stdio will not link in that mode; everything that needs only abort()
   and exit(), which is most of gcc.c-torture/execute, will.
   build-support.sh picks the mode by probing.  */

#ifdef MB_NO_LIBC

#define UART ((volatile unsigned int *) 0x84000000)
typedef unsigned long mb_size_t;
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }

/* write(1, ...) is the whole of what DejaGnu's testglue.c needs from us; it
   formats and prints the status marker itself.  No CR translation, matching
   _write_r in the hosted half of this file -- mb-qemu-run strips CRs and
   DejaGnu's own regexp accepts a bare LF.  */
int write (int fd, const void *buf, mb_size_t n) {
  const char *p = buf; mb_size_t i;
  (void) fd;
  for (i = 0; i < n; i++) putc_ (p[i]);
  return (int) n;
}

/* Nothing is printed here: testglue.c's __wrap_exit has already written the
   status marker by the time this runs.  Spinning is all that is left, and all
   that is wanted -- mb-qemu-run stops QEMU from outside once it sees the
   marker, so this board needs no shutdown device and works on stock QEMU.  */
void exit (int code) {
  (void) code;
  for (;;) ;
}
void abort (void) { puts_ ("abort\r\n"); exit (134); }
void _exit (int c) { exit (c); }
void __assert_func (const char *a, int b, const char *c, const char *d)
{ (void) a; (void) b; (void) c; (void) d; abort (); }

void *memcpy (void *d, const void *s, mb_size_t n)
{ char *p = d; const char *q = s; while (n--) *p++ = *q++; return d; }
void *memmove (void *d, const void *s, mb_size_t n) {
  char *p = d; const char *q = s;
  if (p < q) while (n--) *p++ = *q++;
  else { p += n; q += n; while (n--) *--p = *--q; }
  return d;
}
void *memset (void *d, int c, mb_size_t n)
{ unsigned char *p = d; while (n--) *p++ = (unsigned char) c; return d; }
int memcmp (const void *a, const void *b, mb_size_t n) {
  const unsigned char *p = a, *q = b;
  while (n--) { if (*p != *q) return *p - *q; p++; q++; }
  return 0;
}
void *memchr (const void *s, int c, mb_size_t n) {
  const unsigned char *p = s;
  while (n--) { if (*p == (unsigned char) c) return (void *) p; p++; }
  return 0;
}
mb_size_t strlen (const char *s) { const char *p = s; while (*p) p++; return p - s; }
char *strcpy (char *d, const char *s) { char *p = d; while ((*p++ = *s++)) ; return d; }
char *strcat (char *d, const char *s) { strcpy (d + strlen (d), s); return d; }
int strcmp (const char *a, const char *b)
{ while (*a && *a == *b) { a++; b++; } return (unsigned char) *a - (unsigned char) *b; }
int strncmp (const char *a, const char *b, mb_size_t n) {
  while (n && *a && *a == *b) { a++; b++; n--; }
  return n ? (unsigned char) *a - (unsigned char) *b : 0;
}
char *strchr (const char *s, int c) {
  for (; *s; s++) if (*s == (char) c) return (char *) s;
  return c ? 0 : (char *) s;
}

extern char __heap_start[], __heap_end[];
static char *mb_brk;
void *malloc (mb_size_t n) {
  char *p;
  if (!mb_brk) mb_brk = __heap_start;
  n = (n + 15) & ~(mb_size_t) 15;
  if (mb_brk + n > __heap_end) return 0;
  p = mb_brk; mb_brk += n; return p;
}
void free (void *p) { (void) p; }
void *calloc (mb_size_t a, mb_size_t b) { return memset (malloc (a * b), 0, a * b); }
void *realloc (void *p, mb_size_t n)
{ void *q = malloc (n); if (q && p) memcpy (q, p, n); return q; }

#else /* !MB_NO_LIBC -- the newlib glue */

#include <reent.h>
#include <sys/lock.h>
#include <sys/stat.h>
#include <sys/times.h>
#include <errno.h>
#include <string.h>

#define UART ((volatile unsigned int *) 0x84000000)

static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }

/* --- reentrancy: one thread, so one struct ------------------------------ */
/* A vanilla newlib supplies __getreent itself; only an RTEMS one expects the
   kernel to.  build-support.sh probes for it.  */
#ifdef MB_PROVIDE_REENT
static struct _reent the_reent = _REENT_INIT (the_reent);
struct _reent *__getreent (void) { return &the_reent; }
# define MB_REENT (&the_reent)
#else
# define MB_REENT _REENT
#endif

/* --- locking: one thread, so nothing to contend for -------------------- */
/* Only an RTEMS newlib locks stdio against these.  */
#ifdef MB_PROVIDE_LOCKS
void _Mutex_Acquire (struct _Mutex_Control *m) { (void) m; }
void _Mutex_Release (struct _Mutex_Control *m) { (void) m; }
void _Mutex_recursive_Acquire (struct _Mutex_recursive_Control *m) { (void) m; }
void _Mutex_recursive_Release (struct _Mutex_recursive_Control *m) { (void) m; }
#endif

void _init (void) { }
void _fini (void) { }

/* --- exit: just stop.  DejaGnu's testglue.c has already written the status
   marker through write(), which is why nothing is printed here. ----------- */
void _exit (int code) {
  (void) code;
  /* Spin: mb-qemu-run stops QEMU once it sees the marker.  Deliberately not
     writing to a shutdown device -- petalogix-s3adsp1800 has none upstream,
     and relying on a downstream addition would make this board unusable by
     anyone else.  */
  for (;;) ;
}

void __assert_func (const char *f, int l, const char *fn, const char *e) {
  (void) f; (void) l; (void) fn; (void) e;
  puts_ ("assertion failed\r\n");
  _exit (134);
}

/* --- heap: bump allocator.  The execute tests do not stress free(). ----- */
extern char __heap_start[], __heap_end[];
static char *brk_ptr;

void *_sbrk_r (struct _reent *r, ptrdiff_t incr) {
  char *prev;
  if (!brk_ptr) brk_ptr = __heap_start;
  if (brk_ptr + incr > __heap_end) { r->_errno = ENOMEM; return (void *) -1; }
  prev = brk_ptr; brk_ptr += incr; return prev;
}
void *_sbrk (ptrdiff_t incr) { return _sbrk_r (MB_REENT, incr); }

/* A vanilla newlib brings its own malloc over _sbrk; an RTEMS one does not,
   expecting the kernel heap.  Defining ours unconditionally would collide on
   the former, so build-support.sh probes.  */
#ifdef MB_PROVIDE_MALLOC
static void *bump (size_t n) {
  void *p;
  if (!brk_ptr) brk_ptr = __heap_start;
  n = (n + 15) & ~(size_t) 15;
  if (brk_ptr + n > __heap_end) return 0;
  p = brk_ptr; brk_ptr += n; return p;
}
void *_malloc_r (struct _reent *r, size_t n)
{ void *p = bump (n); if (!p) r->_errno = ENOMEM; return p; }
void  _free_r (struct _reent *r, void *p) { (void) r; (void) p; }
void *_calloc_r (struct _reent *r, size_t a, size_t b) {
  void *p = _malloc_r (r, a * b);
  if (p) memset (p, 0, a * b);
  return p;
}
void *_realloc_r (struct _reent *r, void *p, size_t n) {
  void *q = _malloc_r (r, n);
  if (q && p) memcpy (q, p, n);
  return q;
}
void *malloc (size_t n) { return _malloc_r (MB_REENT, n); }
void  free (void *p) { (void) p; }
void *calloc (size_t a, size_t b) { return _calloc_r (MB_REENT, a, b); }
void *realloc (void *p, size_t n) { return _realloc_r (MB_REENT, p, n); }
#endif /* MB_PROVIDE_MALLOC */

/* --- syscalls ---------------------------------------------------------- */
_ssize_t _write_r (struct _reent *r, int fd, const void *buf, size_t len) {
  const char *p = buf;
  (void) r; (void) fd;
  for (size_t i = 0; i < len; i++) putc_ (p[i]);
  return (_ssize_t) len;
}
/* Plain write(), not just the reentrant form: this newlib expects the OS to
   provide the POSIX entry points, and DejaGnu's testglue.c calls write(1, ...)
   directly to print the status marker.  Without this the glue links with three
   undefined references to write and no test can run.  */
_ssize_t write (int fd, const void *buf, size_t len) {
  return _write_r (MB_REENT, fd, buf, len);
}
_ssize_t _read_r (struct _reent *r, int fd, void *buf, size_t len)
{ (void) r; (void) fd; (void) buf; (void) len; return 0; }
int _close_r (struct _reent *r, int fd) { (void) r; (void) fd; return -1; }
int _fstat_r (struct _reent *r, int fd, struct stat *st)
{ (void) r; (void) fd; st->st_mode = S_IFCHR; return 0; }
int _isatty_r (struct _reent *r, int fd) { (void) r; (void) fd; return 1; }
_off_t _lseek_r (struct _reent *r, int fd, _off_t off, int dir)
{ (void) r; (void) fd; (void) off; (void) dir; return 0; }
int _open_r (struct _reent *r, const char *p, int f, int m)
{ (void) p; (void) f; (void) m; r->_errno = ENOENT; return -1; }
int _kill_r (struct _reent *r, int pid, int sig)
{ (void) pid; (void) sig; r->_errno = EINVAL; return -1; }
int _getpid_r (struct _reent *r) { (void) r; return 1; }
clock_t _times_r (struct _reent *r, struct tms *b) { (void) r; (void) b; return (clock_t) -1; }
int _gettimeofday_r (struct _reent *r, struct timeval *tv, void *tz)
{ (void) tv; (void) tz; r->_errno = ENOSYS; return -1; }

#endif /* MB_NO_LIBC */
