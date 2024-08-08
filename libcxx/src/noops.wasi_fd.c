// attempt to neutralize import dependencies by turning wasi filesystem
// operations into benign "no-ops" -- humbletim 2024.08.07

#ifdef __cplusplus
extern "C" {
#endif

#define POLYFILL __attribute__((weak))
#define USING extern
#define EXPORT(x) __attribute__((export_name(x))) 

#define YYYYMMDD(yyyy, mmdd) ((((unsigned long long)yyyy) << 32) + mmdd)
#define VERSION YYYYMMDD('2024', '0807')

EXPORT(".noops.wasi_fd.version") unsigned long long wasi_fd_version() { return VERSION; }

#define EBADF 0x0008

#define STUB { return EBADF; }
POLYFILL int  __wasi_fd_prestat_get      (int a, int b) STUB
POLYFILL int  __wasi_fd_prestat_dir_name (int a, int b, int c) STUB 
POLYFILL int  __wasi_fd_fdstat_set_flags (int a, int b) STUB
POLYFILL int  __wasi_fd_write            (int a,int b,int c, int d) STUB
POLYFILL int  __wasi_fd_close            (int a) STUB
POLYFILL int  __wasi_fd_seek             (int a, long long b, int c, int d) STUB
POLYFILL int  __wasi_fd_fdstat_get       (int a, int b) STUB
POLYFILL int  __wasi_fd_read             (int a, int b, int c, int d) STUB
POLYFILL int  __wasi_path_open           (int a, int b, int c, int d, long long e, long long f, int g, int h) STUB

#ifdef __cplusplus
} // extern "C"
#endif
