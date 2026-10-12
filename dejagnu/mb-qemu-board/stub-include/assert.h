#ifndef MB_STUB_ASSERT_H
#define MB_STUB_ASSERT_H
void abort (void) __attribute__ ((__noreturn__));
#ifdef NDEBUG
# define assert(e) ((void) 0)
#else
# define assert(e) ((e) ? (void) 0 : abort ())
#endif
#endif
