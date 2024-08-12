#include <libcxx.hpp>
#include <nlohmann-json.cxx>

using json = nlohmann::json;

EXPORT_NAME("xmain") int xmain() {
  __wasm_call_ctors();
  
  // Using (raw) string literals and json::parse
  json ex1 = json::parse(R"(
    {
      "pi": 3.141,
      "happy": true
    }
  )");

  // Using user-defined (raw) string literals
  using namespace nlohmann::literals;
  json ex2 = R"(
    {
      "pi": 3.141,
      "happy": true
    }
  )"_json;
  
  // Using initializer lists
  json ex3 = {
    {"happy", true},
    {"pi", 3.141},
  };

  fprintf(stdout, "ex1: %s\n", ex1.dump().c_str());
  fprintf(stdout, "ex2: %s\n", ex2.dump().c_str());
  fprintf(stdout, "ex3: %s\n", ex3.dump().c_str());

  __wasm_call_dtors();
  return 0;
}
