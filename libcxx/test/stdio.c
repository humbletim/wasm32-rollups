#include <libc.h>

EXPORT_NAME("xmain") int main() {
  printf("[printf] hi &main == %p\n", main);
  fprintf(stdout, "[fprintf(stdout)] hi &main == %p\n", main);
  fflush(stdout);
  fprintf(stderr, "[fprintf(stderr)] hi &main == %p\n", main);

  int written;
  written = fwrite("asdf", 1, 4, stdout);
  fprintf(stdout, "...written=%d (stdout)\n", written);
  fflush(stdout);

  written = fwrite("asdf", 1, 4, stderr);
  fprintf(stderr, "...written=%d (stderr)\n", written);
  fflush(stderr);

  putchar('p');putchar('u');putchar('t');putchar('c');putchar('h');putchar('a');putchar('r');putchar(' ');putchar('h');putchar('i');putchar('\n');
  puts("puts() hi\n");
  printf("printf()\n");
  //printf("tmp=%p\n", tmp);
  FILE* f = fopen("/tmp/404", "rb");
  printf("f=%p %d %s\n", f, errno, strerror(errno));
  if (f)fclose(f);
  fflush(stdout);fflush(stderr);
  return 123;
}

