declare -F diff_defines >/dev/null || { echo "meant to be sourced from libcxx/build.sh..." ; exit 2;  }
build_json() {( set -Euo pipefail ;
    local version=v3.11.3
    local json=$(dirname $BASH_SOURCE)

    test -f $json/nlohmann-json.${version}.hpp || wget -c -nv -O $json/nlohmann-json.${version}.hpp https://raw.githubusercontent.com/nlohmann/json/${version}/single_include/nlohmann/json.hpp
    CXX="$CXX -isystem." diff_defines c++ staging/libcxx-static/libcxx-wasm32.hpp "$json/nlohmann-json.${version}.hpp" \
	| grep -v '#define NLOHMANN_JSON_PASTE' > scratch/JSON.defines
    (
	echo "// SOURCE: https://github.com/nlohmann/json @ ${version}"
	CXX="$CXX -P" make_header c++ JSON <( cat "$json/nlohmann-json.${version}.hpp" | grep -vE '#\s*include' )
    ) > staging/libcxx-static/nlohmann-json.cxx || exit 56
    test -f $json/nlohmann-json.license.txt || wget -c -nv -O $json/nlohmann-json.license.txt https://raw.githubusercontent.com/nlohmann/json/${version}/LICENSE.MIT
    cp -av $json/nlohmann-json.license.txt staging/libcxx-static/nlohmann-json.license.txt
    cp -av $json/test-json.cpp staging/libcxx-static/nlohmann-json.test.cpp
)}

build_json


