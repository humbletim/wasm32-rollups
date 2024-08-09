#ifdef __cplusplus
extern "C" {
#endif

#define POLYFILL __attribute__((weak))
#define USING extern
#define EXPORT(x) __attribute__((export_name(x))) 

#define YYYYMMDD(yyyy, mmdd) ((((unsigned long long)yyyy) << 32) + mmdd)
#define VERSION YYYYMMDD('2024', '0807')

EXPORT(".noops.cxa.version") unsigned long long cxa_version() { return VERSION; }

USING void abort();

  //#define ASSUME_STDIO 1
#ifdef ASSUME_STDIO
  USING int printf(const char *format, ...);
  USING struct _IO_FILE* const stdout;
  USING int fflush(struct _IO_FILE* const);
  #define TRACE { printf(__FUNCTION__); fflush(stdout); }
#else
  #define TRACE /**/
#endif

POLYFILL void* __cxa_allocate_exception(int sz) {
  TRACE;
  static unsigned char cxabuffer[4096];
  return cxabuffer;
}

POLYFILL void  __cxa_throw(int ptr, int type, int destructor) {
  TRACE;
#ifdef ASSUME_STDIO
  unsigned int ip = *(unsigned int*)ptr;
  printf("[__cxa_throw] type=%s ptr=%s\n", ((const char*)ip)+16, ((const char*)ip)+12);
  fflush(stdout);
#endif
  abort();
}

POLYFILL int  __cxa_begin_catch(int a)                  { TRACE; return 0; }
POLYFILL int  __cxa_uncaught_exception()                { TRACE; return 0; }
POLYFILL void __cxa_rethrow()                           { TRACE; return;   }
POLYFILL void __cxa_rethrow_primary_exception(int a)    { TRACE; return;   }
POLYFILL void __cxa_increment_exception_refcount(int a) { TRACE; return;   }
POLYFILL void __cxa_decrement_exception_refcount(int a) { TRACE; return;   }

#ifdef __cplusplus
} // extern "C"
#endif
