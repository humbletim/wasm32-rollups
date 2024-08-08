// this header allows C wasm code to cross-compile easier by automatically
// including the amalgamated wasm32 header or falling back for non-wasm32
// targets to the underyling set of plain system headers.

#pragma once
#ifdef __wasm32__
  #include <libc-wasm32.h>
  #define EXPORT_NAME(x) __attribute__((export_name(x)))
#else
  #include <libc-dynamic.h>
  __attribute__((weak)) extern "C" void __wasm_call_ctors() {}
  #define EXPORT_NAME(x) /* x */
#endif
