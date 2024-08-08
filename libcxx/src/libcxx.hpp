// this header allows C++ wasm code to cross-compile easier by automatically
// including the amalgamated wasm32 header or falling back for non-wasm32
// targets to the underyling set of plain system headers.

#pragma once
#ifdef __wasm32__
  #include <libcxx-wasm32.hpp>
  #define EXPORT_NAME(x) __attribute__((export_name(x)))
#else
  #include <libcxx-dynamic.hpp>
  __attribute__((weak)) extern "C" void __wasm_call_ctors() {}
  #define EXPORT_NAME(x) /* x */
#endif
