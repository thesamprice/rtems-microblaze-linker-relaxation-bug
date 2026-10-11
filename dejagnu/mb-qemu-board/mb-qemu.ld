/* 64MB of RAM from 0x90000000, which is what petalogix-s3adsp1800 gives us.
   The stack is 4MB: 256KB is not enough for the torture suite (pr28982b and
   memcpy-1 both hang on it).  */
ENTRY(_start)
MEMORY { ram : ORIGIN = 0x90000000, LENGTH = 64M }
SECTIONS {
  .vectors 0x90000000 : { *(.vectors) } > ram
  .text : { *(.text .text.*) } > ram
  .init_array : {
    __init_array_start = .;
    KEEP (*(SORT_BY_INIT_PRIORITY(.init_array.*)))
    KEEP (*(.init_array))
    __init_array_end = .;
  } > ram
  .fini_array : {
    __fini_array_start = .;
    KEEP (*(.fini_array)) KEEP (*(.fini_array.*))
    __fini_array_end = .;
  } > ram
  .rodata : { *(.rodata .rodata.*) *(.gcc_except_table*) *(.eh_frame*) } > ram
  .data : { *(.data .data.*) } > ram
  .sdata2 : { _SDA2_BASE_ = . + 0x8000; *(.sdata2 .sdata2.*) *(.sbss2 .sbss2.*) } > ram
  .sdata  : { _SDA_BASE_  = . + 0x8000; *(.sdata .sdata.*) } > ram
  . = ALIGN(4);
  __bss_start = .;
  .sbss : { *(.sbss .sbss.*) } > ram
  .bss  : { *(.bss .bss.*) *(COMMON) } > ram
  . = ALIGN(4);
  __bss_end = .;
  . = ALIGN(16);
  _stack_top = . + 0x400000;
  __heap_start = _stack_top + 16;
  __heap_end = ORIGIN(ram) + LENGTH(ram) - 16;
  _end = __heap_start;
}
