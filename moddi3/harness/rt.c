/* Minimal freestanding runtime so the gcc testsuite fixture can run bare-metal. */
#define UART ((volatile unsigned int *) 0x84000000)
#define CTR  ((volatile unsigned int *) 0xFF000000)
static void putc_ (char c) { while (UART[2] & 0x8) ; UART[1] = (unsigned) c; }
static void puts_ (const char *s) { while (*s) putc_ (*s++); }
void abort (void) { puts_ ("TEST-ABORT\r\n"); CTR[0] = 0; for (;;) ; }
void exit (int c) { puts_ (c ? "TEST-EXIT-NONZERO\r\n" : "TEST-PASS\r\n"); CTR[0] = 0; for (;;) ; }
