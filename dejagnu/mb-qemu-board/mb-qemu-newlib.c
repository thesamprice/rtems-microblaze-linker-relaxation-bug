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
   petalogix-s3adsp1800 provides.  Nothing else is needed: exit() prints a
   status marker and mb-qemu-run stops QEMU from outside.  */
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
static struct _reent the_reent = _REENT_INIT (the_reent);
struct _reent *__getreent (void) { return &the_reent; }

/* --- locking: one thread, so nothing to contend for -------------------- */
void _Mutex_Acquire (struct _Mutex_Control *m) { (void) m; }
void _Mutex_Release (struct _Mutex_Control *m) { (void) m; }
void _Mutex_recursive_Acquire (struct _Mutex_recursive_Control *m) { (void) m; }
void _Mutex_recursive_Release (struct _Mutex_recursive_Control *m) { (void) m; }

void _init (void) { }
void _fini (void) { }

/* --- exit: state the status, because QEMU cannot return one ------------- */
void _exit (int code) {
  puts_ ("\r\n*** EXIT ");
  { char b[12]; int i = 0; unsigned u = (unsigned) code;
    if (!u) putc_ ('0');
    while (u) { b[i++] = (char) ('0' + u % 10); u /= 10; }
    while (i--) putc_ (b[i]); }
  puts_ (" ***\r\n");
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
void *_sbrk (ptrdiff_t incr) { return _sbrk_r (&the_reent, incr); }

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
void *malloc (size_t n) { return _malloc_r (&the_reent, n); }
void  free (void *p) { (void) p; }
void *calloc (size_t a, size_t b) { return _calloc_r (&the_reent, a, b); }
void *realloc (void *p, size_t n) { return _realloc_r (&the_reent, p, n); }

/* --- syscalls ---------------------------------------------------------- */
_ssize_t _write_r (struct _reent *r, int fd, const void *buf, size_t len) {
  const char *p = buf;
  (void) r; (void) fd;
  for (size_t i = 0; i < len; i++) putc_ (p[i]);
  return (_ssize_t) len;
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
