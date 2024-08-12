#ifdef __cplusplus
extern "C" {
#endif

#define POLYFILL __attribute__((weak))
#define USING extern
#define EXPORT(x) __attribute__((export_name(x))) 

#define YYYYMMDD(yyyy, mmdd) ((((unsigned long long)yyyy) << 32) + mmdd)
#define VERSION YYYYMMDD('2024', '0806')

EXPORT(".noops.wasi_libc.version") unsigned long long wasilibc_version() { return VERSION; }
#define EBADF 0x0008

POLYFILL int fclose(int a) { return EBADF; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wbuiltin-requires-header"
POLYFILL struct _IO_FILE* fopen(const char* path, const char* mode) { return 0; }
POLYFILL unsigned long fwrite(const void* ptr, unsigned long size, unsigned long nmemb, struct _IO_FILE *stream) { return nmemb; }

#pragma clang diagnostic pop

POLYFILL unsigned long __fwritex(const unsigned char * s, unsigned long l, struct _IO_FILE *f) { return l; }

POLYFILL char* getenv(const char*) { return 0; }

POLYFILL unsigned int __stack_chk_guard;
POLYFILL void __stack_chk_fail(void) {}

POLYFILL void __wasilibc_initialize_environ(void) {}
POLYFILL void __wasilibc_ensure_environ(void) {}
POLYFILL void __wasilibc_deinitialize_environ(void) {}
POLYFILL void __wasilibc_maybe_reinitialize_environ_eagerly(void) {}
POLYFILL char **__wasilibc_get_environ(void) { return 0; }

POLYFILL void __wasilibc_populate_preopens() { }
POLYFILL int  __wasilibc_find_relpath(const char *path, const char **abs_prefix, char **relative_path, unsigned long relative_path_len) { return -1; }

#ifdef __cplusplus
} // extern "C"
#endif
