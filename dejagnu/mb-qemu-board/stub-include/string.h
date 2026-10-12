#ifndef MB_STUB_STRING_H
#define MB_STUB_STRING_H
typedef __SIZE_TYPE__ size_t;
void *memcpy (void *, const void *, size_t);
void *memmove (void *, const void *, size_t);
void *memset (void *, int, size_t);
int memcmp (const void *, const void *, size_t);
void *memchr (const void *, int, size_t);
size_t strlen (const char *);
char *strcpy (char *, const char *);
char *strcat (char *, const char *);
int strcmp (const char *, const char *);
int strncmp (const char *, const char *, size_t);
char *strchr (const char *, int);
#endif
