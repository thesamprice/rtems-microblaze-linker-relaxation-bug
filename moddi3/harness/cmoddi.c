/* The generic libgcc __moddi3, transcribed from libgcc/libgcc2.c.
   Named c_moddi3 so it can be linked beside the assembly one.
   __udivmoddi4 is NOT in microblaze's LIB2FUNCS_EXCLUDE, so libgcc supplies it. */
typedef long long DWtype;
typedef unsigned long long UDWtype;
typedef int Wtype;
struct DWstruct { Wtype high, low; };          /* big-endian layout */
struct DWstruct_le { Wtype low, high; };
extern UDWtype __udivmoddi4 (UDWtype, UDWtype, UDWtype *);

DWtype
c_moddi3 (DWtype u, DWtype v)
{
  Wtype c = 0;
  DWtype w;
#ifdef __MICROBLAZEEL__
  union { DWtype ll; struct DWstruct_le s; } uu = {.ll = u}, vv = {.ll = v};
#else
  union { DWtype ll; struct DWstruct s; } uu = {.ll = u}, vv = {.ll = v};
#endif
  if (uu.s.high < 0)
    c = ~c, uu.ll = -uu.ll;
  if (vv.s.high < 0)
    vv.ll = -vv.ll;
  (void) __udivmoddi4 (uu.ll, vv.ll, (UDWtype *) &w);
  if (c)
    w = -w;
  return w;
}
