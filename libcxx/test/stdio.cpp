#include <libcxx.hpp>

// TODO: std::cout / std::cerr buffering is broken somewhere currently...
// (however, fprintf(stderr, ...) & similar seem to be reliably working)

EXPORT_NAME("xmain") int main() {
  __wasm_call_ctors(); // has to be initialized to utilize std::cout

  fprintf(stdout, "[fprintf(stdout)] hello from %s:%d\n", __FUNCTION__, __LINE__);

  std::cout << "[std::cout] hi from line " << __LINE__ << std::endl;
  std::cerr << "[std::cerr] hi from line " << __LINE__ << std::endl;

  fprintf(stderr, "[fprintf(stderr)] from line %d\n", __LINE__);

  std::cout << "[std::cout] from line " << __LINE__ << std::endl;
  std::cerr << "[std::cerr] hi from line " << __LINE__ << std::endl;
  fprintf(stdout, "[fprintf(stdout)] goodbye from %s:%d\n", __FUNCTION__, __LINE__);
  fflush(stdout);
  fprintf(stdout, "[fprintf(stdout)] goodbye from %s:%d\n", __FUNCTION__, __LINE__);
  fprintf(stderr, "[fprintf(stderr)] goodbye from line %d\n", __LINE__);

  __wasm_call_dtors(); // somewhat optional in wasm use case, but ensures stdout/stderr fflush'd at exit
  return 0;
}
