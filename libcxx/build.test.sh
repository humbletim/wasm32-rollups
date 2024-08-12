#!/bin/bash
set -Euo pipefail
export CC=clang-17 CXX=clang++-17
./staging/bin/w32cc-17 test/main.c -o main.c.baremetal.wasm -Oz -s
./staging/bin/w32c++-17 test/main.cpp -o main.cxx.baremetal.wasm -Oz -s
./staging/bin/w32c++-17 test/main.cpp -o main.cxx.wasm
./staging/bin/w32c++-17 test/stdio.cpp -o stdio.cxx.wasm
./staging/bin/w32cc-17 test/stdio.c -o stdio.c.wasm
./staging/bin/w32c++-17 -lqwasi-capture test/stdio.cpp -o stdio.cxx.capture.wasm
./staging/bin/w32cc-17  -lqwasi-capture test/stdio.c -o stdio.c.capture.wasm
./staging/bin/w32c++-17 -lqwasi-capture test/stdio.cpp -o stdio.cxx.baremetal.capture.wasm -Oz -Wl,--strip-debug
./staging/bin/w32c++-17 -lqwasi-capture staging/libcxx-static/nlohmann-json.test.cpp -o test-json.capture.wasm -Oz -Wl,--strip-debug

for x in *.wasm ; do
    echo "### $x" ; echo '```' ; ./staging/bin/w32info $x ; echo '```' ;
done
