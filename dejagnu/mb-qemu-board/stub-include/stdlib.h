#ifndef MB_STUB_STDLIB_H
#define MB_STUB_STDLIB_H
typedef __SIZE_TYPE__ size_t;
void abort (void) __attribute__ ((__noreturn__));
void exit (int) __attribute__ ((__noreturn__));
void *malloc (size_t);
void *calloc (size_t, size_t);
void *realloc (void *, size_t);
void free (void *);
int abs (int);
long labs (long);
#endif
