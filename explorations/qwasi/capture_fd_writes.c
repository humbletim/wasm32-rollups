// mode: zerodep c/++

#ifdef __cplusplus
extern "C" {
#endif

#define POLYFILL __attribute__((weak))
#define EXPORT(x) __attribute__((export_name(x))) 

EXPORT(".qwasi.capture_fd_writes.version")
unsigned long long qwasi_capture_fd_writes_version() { return 0x20240810; }

static inline struct Captured* _captured();
EXPORT(".struct.captured_fd_writes{i32;u8[]}")
int captured_fd_writes() { return (int)_captured(); }

#define EBADF 0x0008
typedef struct __wasi_iovec_t {
  unsigned char* buf;
  int buf_len;
} iovec_t;

#define CAPTURE_BYTESIZE 8192
typedef struct Captured {
  int buffer_offset;
  unsigned char buffer[CAPTURE_BYTESIZE];
} Captured;
static inline struct Captured* _captured() {
  static struct Captured v;
  return &v;
}

POLYFILL int __wasi_fd_write(int fd, iovec_t* iovs, int iov_count, unsigned long* nwritten) {
  //if (!( fd == 1 || fd == 2 )) return EBADF;
  
  struct Captured *cap = _captured();
  for (int i = 0; i < iov_count; i++) {
    if (iovs[i].buf_len > CAPTURE_BYTESIZE) {
      cap->buffer[0] = '>';
      return EBADF; // TODO: appropriate error constant
    }
    if (iovs[i].buf_len < 0) {
      cap->buffer[0] = '<';
      return EBADF; // TODO: appropriate error constant
    }
    if (iovs[i].buf_len == 0) continue;
    
    if (cap->buffer_offset + iovs[i].buf_len > CAPTURE_BYTESIZE) {
      cap->buffer[0] = '|';
      cap->buffer_offset = 1;
    }

    for (int j = 0; j < iovs[i].buf_len; j++) cap->buffer[cap->buffer_offset++] = iovs[i].buf[j];
    //__builtin_memcpy(cap->buffer + cap->buffer_offset, iovs[i].buf, iovs[i].buf_len);
    //cap->buffer_offset += iovs[i].buf_len;

    if (nwritten) *nwritten += iovs[i].buf_len;
  }

  return iov_count;
}

struct _IO_FILE;
extern struct _IO_FILE const* stderr;
extern struct _IO_FILE const* stdout;

POLYFILL unsigned long __fwritex(const unsigned char * ptr, unsigned long size, struct _IO_FILE *stream) {
  //if (!(stream == stdout || stream == stderr)) return -1;
  iovec_t tmp;
  tmp.buf = (unsigned char*)ptr;
  tmp.buf_len = size;
  unsigned long nwritten = 0;
  int r = __wasi_fd_write(stream == stdout ? 1 : stream == stderr ? 2 : 2, &tmp, 1, &nwritten);
  return nwritten;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wbuiltin-requires-header"
POLYFILL unsigned long fwrite(const void* ptr, unsigned long size, unsigned long nmemb, struct _IO_FILE *stream) {
  unsigned long nwritten = 0;
  for (int i=0; i < nmemb; i++) {
    nwritten += __fwritex((unsigned char*)ptr + (size * i), size, stream);
  }
  return nwritten;
}
#pragma clang diagnostic pop

#ifdef __cplusplus
} // extern "C"
#endif
