#include <libcxx.hpp>
#include <glm.cxx>

struct AttributeSet {
  glm::vec3 position;
  glm::vec3 color;
};
template <size_t N> using Attributes = std::array<AttributeSet, N>;

Attributes<256> attributes{};

EXPORT_NAME("xmain") int32_t main() {
  static int N=0;
  glm::vec3& a0 { attributes[0].position };
  __builtin_dump_struct( &a0, printf );
  __builtin_dump_struct( &attributes[0], printf );
  attributes[0].position.x = N++;
  printf("hello '%s'\n", typeid(int ).name());
  printf("/hello '%s'\n", typeid(int ).name());
  return 0;
}

