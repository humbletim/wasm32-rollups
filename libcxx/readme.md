*work in progress / draft readme*

# libcxx - static libc++ for WASM

Develop standalone C++ WASM modules a little more easily.

`libcxx` provides a statically compiled libc++ standard library, minimizing dependencies and potentially simplifying enthusiast workflows.

**Key Features:**

* **Universality:** Aims to enable a fundamental and practical subset of everyday C++, reducing toolchain entropy to ensure compatibility across different environments.
* **Colloquial C++ Usage:** Sustains familiar and intuitive C++ language experience, providing access to features like `std::string`, `std::array`, and lambdas via compile-time dependencies only.
* **WASI Agnosticism:**  While not prohibiting WASI usage, the core `libcxx` remains independent (or at least not as inherently tethered) to WASI features. This is achieved through:
    * **Isolating WASI Features:**  WASI-specific functionalities are separated into a distinct `libwasi.a` library.
    * **Capturing WASI syscalls:**  An innovative approach explores capturing aspects like `fd_writes` (the WASI primitive that C/C++ `fwrite` and similar rely on), for later optional retrieval by the host, showcasing flexibility in handling WASI interactions.
* **Monolithic Amalgamation:**  Accessible as a single, self-contained `libcxx.hpp` header and `libcxx.a` static library (pre-processed and distilled for WASM32).
* **Bare-Metal Compatibility:**  Designed for seamless integration with LLVM `clang++` in a bare-metal WASM32 compilation environment.

**Build Process:**

The project utilizes a custom build script (`build.sh`) to amalgamate and preprocess upstream libc++ resources. Currently, it relies on prebuilt wasm32 Ubuntu `.deb` packages, with a future goal of migrating to compiling from source.

### Why Choose libcxx?

You probably should not; instead choose Emscripten, wasi-sdk or a similar "batteries included" C++ toolchain solution (especially if looking to port existing C++ code to Wasm wholemeal).

However, for crafting basic portable modules (that just happen to be or would like to become authored using modern C++ conventions), this project addresses several related challenges:

* **Emscripten's Extensive Runtime Dependencies:**  Emscripten often requires significant host runtime glue code, hindering the creation of truly standalone modules. Support for non-Web scenarios is steadiliy improving. [TODO: add resource links to relevant emsdk resources]
* **wasi-sdk / wasi-libc's Inadvertent WASI Coupling:**  wasi-sdk can inadvertently introduce WASI host dependencies, even when filesystem methods aren't being knowingly called upon.
* **host imports represent a barrier to entry in the general case:** Vendor-locked .wasm artifacts tend to negotiatiate API surface areas with specific host runtimes or situations in advance; but to imagine a more broadly redeployable kind of .wasm artifacts, any and all niche host import requirements tend to get in the way. By default, `libcxx` strives to create WASM modules *without any host import expectations*, enabling a kind of bare-metal ecosystem-wide wasm32 compatibility.

### TODO: placeholder example
```c++
// main.cpp
#include <libcxx.hpp>

EXPORT_NAME("xmain") int main(void) {
  std::function func = []{ return "hi"; };
  std::string str{ func() };
  return -123;
}
```
#### via libcxx (this project) clang++-17 wrapper:
```sh
$ staging/bin/w32c++-17 main.cpp -o main.wasm
```
#### or vanila clang++-17 direct invocation
```sh
$ clang++-17 --target=wasm32 -nostdinc -nostdlib -Wl,--no-entry -fno-exceptions -isystem$BASE -Wl,$BASE/libcxx.a -Wl,-L$BASE "$@" -Wl,-lqwasi
```
#### quickly testing the resulting .wasm artifact
```
$ node -e 'WebAssembly.instantiate(require("fs").readFileSync("main.wasm"))
            .then((m)=>console.log(m.instance.exports.xmain()))'
-123
```

## Caveats and Considerations:

* **Inter-independence of libc and libc++:**  The project currently emerges both a `libc-static` and `libcxx-static` basis, for crafting LLVM-compiled wasm32 C modules or C++ modules, respectively. This deviates from conventions that instead treat C and C++ as stacked (ie: `-lc -lc++ -lc++abi` internally). With libcxx, you either link against libcxx-static or libc-static, never both, as they are each all-inclusive to their purposes.
* **No C++ Exceptions:**  While technically possible to compile code with try/catch blocks, exception support isn't yet standardized across WASM runtimes.
* **Memory Management:**  `libcxx` doesn't itself impose specific memory allocation rituals, by default picking up symbols for `malloc` and similar via wasi-libc `dalloc` fallback. Note that if your C++ module expects static global initializaters, it is necessary to invoke __wasm_call_ctors(). LLVM internal magic (non-bare-metal invocation) suggests adopting `_initialize()` and `_start()` conventions (for static init and main entry point), but those were too imposing to my use cases, so no such magic is enabled by default with libcxx. 
* **Bare-Metal Compatibility Focus:**  The term "bare-metal" here refers to creating 100% standalone WASM artifacts with zero host import expectations, rather than the absence of libc++ or libc entirely.

## Future Directions:

* **Migrating to Compiling from Source:**  Enhance control over the build process and ensure long-term maintainability.
* **Expanding 'Inverted WASI' Capabilities:**  Explore further applications and use cases for the "inverted WASI" experiment.

## Contributing:

This is currently a personal project, but feel free to reach out if you have ideas or would like to collaborate.

## License:

* For amalgamated upstream dependencies, see `staging/libcxx-static/upstream-licenses.txt` and similar for `libc-static`.
* A license for this repository will be added soon.