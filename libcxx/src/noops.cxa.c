// attempt to neutralize cxa exception dependencies by turning would-be host imports
// into benign "no-ops" -- humbletim 2024.08.07

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
USING int printf(const char *format, ...);
USING struct _IO_FILE* const stdout;
USING int fflush(struct _IO_FILE* const);

POLYFILL void* __cxa_allocate_exception(int sz) {
  printf(__FUNCTION__); fflush(stdout);
  static unsigned char cxabuffer[4096];
  return cxabuffer;
}

POLYFILL int __cxa_begin_catch(void *exceptionObject) { printf(__FUNCTION__); fflush(stdout); return 0; }
POLYFILL void __cxa_rethrow() { printf(__FUNCTION__); fflush(stdout); return ; }
POLYFILL int __cxa_uncaught_exception() { printf(__FUNCTION__); fflush(stdout); return 0 ; }
POLYFILL void __cxa_rethrow_primary_exception(int a) { printf(__FUNCTION__); fflush(stdout); return ; }
POLYFILL void __cxa_increment_exception_refcount(int a) { printf(__FUNCTION__); fflush(stdout); return ; }
POLYFILL void __cxa_decrement_exception_refcount(int a) { printf(__FUNCTION__); fflush(stdout); return ; }

POLYFILL void  __cxa_throw(int ptr, int type, int destructor) {
  unsigned int ip = *(unsigned int*)ptr;
  printf("[__cxa_throw] type=%s ptr=%s\n", ((const char*)ip)+16, ((const char*)ip)+12);
  // TODO: above offsets calculated manually to attempt a last-ditch effort before aborting
  // to provide clues for the developer
  // auto a = ((const char*)ip);
  // auto b = ((const char*)type);
  // for ( int i=0; i < 100; i++) {
  //   printf("THROWN[%d]: type=%s ptr=%s\n", i,a+i,b+i);
  //  }
  fflush(stdout);
  abort();
}

#ifdef __cplusplus
} // extern "C"
#endif
