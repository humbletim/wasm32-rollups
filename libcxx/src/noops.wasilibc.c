// attempt to neutralize import dependencies by turning "wasilibc"
// operations into benign "no-ops" -- humbletim 2024.08.07

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
#pragma clang diagnostic pop

POLYFILL void __wasilibc_populate_preopens() { }
POLYFILL int  __wasilibc_find_relpath(const char *path, const char **abs_prefix, char **relative_path, unsigned long relative_path_len) {  return -1; }

#ifdef __cplusplus
} // extern "C"
#endif
