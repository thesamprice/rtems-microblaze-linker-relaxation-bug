#ifndef MB_STUB_STDIO_H
#define MB_STUB_STDIO_H
/* Declarations only.  There is no stdio in MB_NO_LIBC mode, so a test that
   actually calls these compiles and then fails to link -- which is the
   truthful result, rather than a silently skipped test.  */
typedef __SIZE_TYPE__ size_t;
typedef struct _MB_FILE MB_FILE;
#define FILE MB_FILE
extern FILE *stdin, *stdout, *stderr;
int printf (const char *, ...);
int fprintf (FILE *, const char *, ...);
int sprintf (char *, const char *, ...);
int snprintf (char *, size_t, const char *, ...);
int puts (const char *);
int putchar (int);
int fputs (const char *, FILE *);
int fflush (FILE *);
#endif
