/* Freestanding runtime for running gcc.c-torture/execute bare-metal under
   qemu-system-microblaze.  The suite is written to need almost nothing: a
   test signals failure with abort() and success by returning from main or
   calling exit(0).  The few string/memory helpers are here because GCC
   expands some builtins into calls to them.  */
#define UART ((volatile unsigned int *) 0x84000000)
#define CTR  ((volatile unsigned int *) 0xFF000000)
typedef unsigned long size_t;

static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }

void exit (int c) {
  puts_ (c ? "TEST-EXIT-NONZERO\r\n" : "TEST-PASS\r\n");
  CTR[0] = 0; for (;;) ;
}
void abort (void) { puts_ ("TEST-ABORT\r\n"); CTR[0] = 0; for (;;) ; }
void __assert_func (const char *a, int b, const char *c, const char *d) { abort (); }
void __assert_fail (const char *a, const char *b, unsigned c, const char *d) { abort (); }

void *memcpy (void *d, const void *s, size_t n) {
  char *p = d; const char *q = s; while (n--) *p++ = *q++; return d;
}
void *memmove (void *d, const void *s, size_t n) {
  char *p = d; const char *q = s;
  if (p < q) { while (n--) *p++ = *q++; }
  else { p += n; q += n; while (n--) *--p = *--q; }
  return d;
}
void *memset (void *d, int c, size_t n) {
  unsigned char *p = d; while (n--) *p++ = (unsigned char) c; return d;
}
int memcmp (const void *a, const void *b, size_t n) {
  const unsigned char *p = a, *q = b;
  while (n--) { if (*p != *q) return *p - *q; p++; q++; }
  return 0;
}
size_t strlen (const char *s) { const char *p = s; while (*p) p++; return p - s; }
char *strcpy (char *d, const char *s) { char *p = d; while ((*p++ = *s++)) ; return d; }
char *strcat (char *d, const char *s) { strcpy (d + strlen (d), s); return d; }
int strcmp (const char *a, const char *b) {
  while (*a && *a == *b) { a++; b++; }
  return (unsigned char) *a - (unsigned char) *b;
}
int strncmp (const char *a, const char *b, size_t n) {
  while (n && *a && *a == *b) { a++; b++; n--; }
  return n ? (unsigned char) *a - (unsigned char) *b : 0;
}
char *strchr (const char *s, int c) {
  for (; *s; s++) if (*s == (char) c) return (char *) s;
  return c ? 0 : (char *) s;
}

/* Bump allocator: the tests that allocate never free in anger.  */
extern char _heap_start[];
static size_t off;
void *malloc (size_t n) { void *p = _heap_start + off; off += (n + 15) & ~(size_t) 15; return p; }
void *calloc (size_t a, size_t b) { return memset (malloc (a * b), 0, a * b); }
void *realloc (void *p, size_t n) { void *q = malloc (n); if (p) memcpy (q, p, n); return q; }
void free (void *p) { (void) p; }

int printf (const char *f, ...) { (void) f; return 0; }
int puts (const char *s) { (void) s; return 0; }
int putchar (int c) { (void) c; return c; }
void *memchr (const void *s, int c, size_t n) {
  const unsigned char *p = s;
  while (n--) { if (*p == (unsigned char) c) return (void *) p; p++; }
  return 0;
}
