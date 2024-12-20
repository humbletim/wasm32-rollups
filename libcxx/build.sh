#!/bin/bash

# libcxx wasm32 hybrid amalgamation script that fetches prebuilt (wasm32)
# libc++.a and related .deb's from upstream ubuntu repos and amalgamates
# everything together into a singular static libcxx.a + libcxx.hpp

set -Euo pipefail  # Exit on error

function die() {
    echo "die: $@" >&2
    exit 1
}

# === Configuration ===
V=17  # LLVM version 
CXX="/usr/bin/clang++-$V"
CC="/usr/bin/clang-$V"
AR="/usr/bin/llvm-ar-$V"
RANLIB="/usr/bin/llvm-ranlib-$V"
CXX_HEADERS_DIR="scratch/usr/lib/llvm-${V}/include/wasm32-wasi/c++/v1"
C_HEADERS_DIR="scratch/usr/include/wasm32-wasi"
LLVM_HEADERS_DIR="/usr/lib/llvm-${V}/lib/clang/${V}/include"

C_LIBS=( "c" "clang_rt.builtins-wasm32" )
CXX_LIBS=( "c++" "c++abi" "${C_LIBS[@]}")

CXX_HEADERS=(
    algorithm
    any
    array
    atomic
    bitset
    cassert
    cctype
    cerrno
    cfloat
    chrono
    climits
    clocale
    cmath
    complex
    cstdarg
    cstddef
    cstdio
    cstdint
    cstdlib
    cstring
    deque
    exception
    filesystem
    forward_list
    functional
    initializer_list
    iomanip
    ios
    iosfwd
    iostream
    istream
    iterator
    limits
    locale
    map
    memory
    numeric
    ostream
    stack
    stdexcept
    string
    string_view
    system_error
    tuple
    type_traits
    unordered_map
    utility
    valarray
    vector
)

C_HEADERS=(
    assert.h
    errno.h
    limits.h
    locale.h
    stdbool.h
    stdint.h
    stdio.h
    string.h
)

C_RESOLVED_HEADERS=()
for header in "${C_HEADERS[@]}"; do
  C_RESOLVED_HEADERS+=("$C_HEADERS_DIR/$header")
done

# Combine header file lists with resolved paths
CXX_RESOLVED_HEADERS=()
for header in "${CXX_HEADERS[@]}"; do
  CXX_RESOLVED_HEADERS+=("$CXX_HEADERS_DIR/$header")
done
CXX_RESOLVED_HEADERS+=("${C_RESOLVED_HEADERS}")

wasm32_baremetal=(
  "--target=wasm32"
  "-nostdinc"
  "-nostdlib"
  "-Wl,--no-entry"
  "-fno-exceptions"
) 

cpp_isystem_dirs=( "$C_HEADERS_DIR" "$LLVM_HEADERS_DIR" )
cpp_flags=(
  "-xc"
  "${cpp_isystem_dirs[@]/#/"-isystem"}"
  "${wasm32_baremetal[@]}"
  "-D__wasi__=1"
  "-Wno-pragma-system-header-outside-header"
  "-Wno-unused-command-line-argument"
)

cxxpp_isystem_dirs=( "$CXX_HEADERS_DIR" "${cpp_isystem_dirs[@]}" )
cxxpp_flags=(
  "-xc++"
  "${cxxpp_isystem_dirs[@]/#/"-isystem"}"
  "${wasm32_baremetal[@]}"
  "-D__wasi__=1"
  "-Wno-pragma-system-header-outside-header"
  "-Wno-unused-command-line-argument"
)

# === Helper Functions ===

# kludges to avoid llvm complaints about userspace "system" headers
declare -A quieters=(
[complex.before]='
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wuser-defined-literals"
'
[complex.after]='
    #pragma clang diagnostic pop
'
)

amalgamate_sources() {
  local file
  for file in "$@"; do
    test ! -v quieters["$(basename $file).before"] || echo "${quieters[$(basename $file).before]}"
    echo "#line 0 \"$file\""
    cat "$file" || die "error processing $file"
    test ! -v quieters["$(basename $file).after"] || echo "${quieters[$(basename $file).after]}"
  done
}

amalgamate_includes() {
  local file
  for file in "$@"; do
    echo "#include <$file>"
  done
}

function preprocess() {
    local mode=$1
    shift
    pp="$CXX ${cxxpp_flags[@]} -E -x$mode"
    [[ "$mode" == "c" ]] && pp="$CXX ${cpp_flags[@]} -E -x$mode"
    $pp "$@"
}

diff_defines() {
    local mode=$1
    local left=$2
    shift 2
    echo "diff_defines $mode (left=$left) " >&2
    preprocess $mode -dM $left > scratch/defines_none.h || exit 1
    preprocess $mode -dM <( amalgamate_includes "$@") > scratch/defines_all.h || exit 2
    diff scratch/defines_none.h scratch/defines_all.h | grep -E '^>' | sed -e 's@^> @@g' \
	| ( grep -v '#define __NEED_' || true ) || true
}

generate_defines() {
    local mode=$1
    shift
    echo "generate_defines $mode " >&2
    diff_defines "$mode" /dev/null "$@"
    # preprocess $mode -dM /dev/null > scratch/defines_none.h
    # preprocess $mode -dM <( amalgamate_includes "$@") > scratch/defines_all.h
    # diff scratch/defines_none.h scratch/defines_all.h | grep -E '^>' | sed -e 's@^> @@g' \
    # 	| ( grep -v '#define __NEED_' || true )
}

unpack_library() {
    local lib=$1
    alib="$(find scratch/ -type f -name "lib${lib}.a")"
    echo "recursively unarchiving ... ${alib}" >&2
    # note: libc.a contains multiple object files named "errno.o"
    #  (hence layered unpacking is needed to preserve (as "ar x'ing would not))
    mkdir -p scratch/$lib.objects
    mkdir -p scratch/$lib.objects.1
    $AR --output=scratch/$lib.objects -x "${alib}"
    level=1
    while [[ $level -lt 10 ]] ; do
	level_dir=scratch/$lib.objects.$level
	mkdir -pv $level_dir
        $AR --output=$level_dir -x -N $level "${alib}" $(ls scratch/$lib.objects) 2>/dev/null || true
	rmdir $level_dir 2>/dev/null && break || true # abort mission after first empty "level" result
	let level=level+1
    done
    # roll-up levels to main scratch/objects
    for x in `ls -1d scratch/$lib.objects.* | sort ` ; do
	uniq=.${x#*objects.}.o
	verbose=
	[[ $uniq == .1.o ]] && uniq= #verbose=
	for y in `ls $x` ; do
	    #test -f scratch/$lib.objects/$y ||
	    cp -a $verbose $x/$y scratch/$lib.objects/$y$uniq
	done
    done
}

# consolidate levels into common folder (ensuring distinct object filenames)
merge_objects_fromlib_tofolder() {
    local lib=$1
    local folder=$2
    test -d "$folder"
    for x in `ls scratch/$lib.objects`; do
	cp -a scratch/$lib.objects/$x $folder/$lib.$x
    done
}

# unpack_library() {
#     local lib=$1
#     alib="$(find scratch/ -type f -name "lib${lib}.a")"
#     echo "recursively unarchiving ... ${alib}" >&2
#     mkdir -p scratch/$lib.objects
#     $AR --output=scratch/$lib.objects -x "${alib}"
#     # ensure first discovered object file is used (rather than last)
#     #$AR --output=scratch/$lib.objects -x -N 1 "${alib}" $(ls scratch/$lib.objects)
#     for x in `ls scratch/$lib.objects`; do
# 	if [[ -f scratch/objects/$x ]] ; then
# 	    #echo "duplicate; perserving... $lib//$x" >&2
# 	    cp -a scratch/$lib.objects/$x scratch/objects/$lib.$x
# 	else
# 	    cp -a scratch/$lib.objects/$x scratch/objects/$x
# 	fi
#     done
# }

repack_library() {
    local lib=$1
    shift
    test -f $lib && rm $lib
    #wasm-ld-17 -r -o $lib.o "$@"
    $AR -cr $lib "$@"
    #$RANLIB $lib
}

generate_protobins() {
    mkdir -p staging/bin

    cat <<EOT > staging/bin/w32c++-$V && chmod a+x staging/bin/w32c++-$V
#!/bin/bash
CXX=\${CXX:-\$((which clang++-17 2>/dev/null || which clang++ 2>/dev/null) | head -1)}
\$CXX --version | grep -E "\\b${V}[.][0-9]+[.][0-9]+\\b" >/dev/null \
    || { echo "Error: clang++-$V (\$CXX) not found; found \$(\$CXX --version|head -1). Please install (and set CXX= if necessary)." >&2; exit 1; }
BASE=\$(dirname \$(dirname \$BASH_SOURCE))/libcxx-static
set -x # display commands used
\$CXX -xc++ ${wasm32_baremetal[@]} -isystem\$BASE -Wl,\$BASE/libcxx.a -Wl,-L\$BASE "\$@" -Wl,-lqwasi
EOT

    cat <<EOT > staging/bin/w32cc-$V && chmod a+x staging/bin/w32cc-$V
#!/bin/bash
CC=\${CC:-\$((which clang-17 2>/dev/null || which clang 2>/dev/null) | head -1)}
\$CC --version | grep -E "\\b${V}[.][0-9]+[.][0-9]+\\b" >/dev/null \
    || { echo "Error: clang-$V (\$CC) not found; found \$(\$CC --version|head -1). Please install (and set CC= if necessary)." >&2; exit 1; }
BASE=\$(dirname \$(dirname \$BASH_SOURCE))/libc-static
\${CC:-clang} -xc ${wasm32_baremetal[@]} -isystem\$BASE -Wl,\$BASE/libc.a -Wl,-L\$BASE "\$@" -Wl,-lqwasi 
EOT

    cat <<EOT > staging/bin/w32info && chmod a+x staging/bin/w32info
#!/bin/bash
file \$1
echo \$(du -hsb \$1 | awk '{ print \$1; }') bytes
BASE=\$(dirname \$BASH_SOURCE)
node \$BASE/detect-module-versions.js \$1
wasm-dis \$1 | grep -E '[(](import|export|global) '
#wasm2wat \$1
EOT
    cp -av src/versions.js staging/bin/detect-module-versions.js
}

# Check LLVM version
$CXX --version | grep -E "\\b${V}[.][0-9]+[.][0-9]+\\b" >/dev/null \
    || { echo "Error: clang++-$V ($CXX) not found; found $($CXX --version|head -1). Please install." >&2; exit 1; }

# Fetch ubuntu (wasm32 architecture) bundled wasi-libc and libc++ etc.
# this acquires latest versions of:
#   libc++-17-dev-wasm32_1%3a17.0.2-1~exp1ubuntu2.1_all.deb
#   libc++abi-17-dev-wasm32_1%3a17.0.2-1~exp1ubuntu2.1_all.deb
#   libclang-rt-17-dev-wasm32_1%3a17.0.2-1~exp1ubuntu2.1_all.deb
#   wasi-libc_0.0~git20230113.4362b18-2_all.deb
# TODO: would prefer to replicate from source but that's for some other rainy day
mkdir -p downloads
test -f downloads/debs.txt || (
    set -Euo pipefail
    cd downloads
    curl -s https://old-releases.ubuntu.com/ubuntu/dists/mantic/universe/binary-amd64/Packages.xz | xzcat \
	| grep -Eo "pool/.*(${V}-dev-wasm32|wasi-libc).*[.]deb" | sed 's@^@http://old-releases.ubuntu.com/ubuntu/@' \
	| tee debs.txt | xargs wget -c -nv
    [ $(cat debs.txt | wc -l) -eq 4 ] \
	|| { echo "expected 4 found packages... but got $(wc -l debs.txt);" ; cat debs.txt ; rm debs.txt ; exit 4 ; }
)

test -f scratch/unpacked.txt || (
    test -d scratch && rm scratch -rf
    mkdir -p scratch
    for x in downloads/*.deb ; do
	dpkg -x $x scratch/
    done

    echo "-- libcxx prep -- " >&2
    mkdir -p scratch/objects
    for lib in "${CXX_LIBS[@]}"; do
	unpack_library $lib
	merge_objects_fromlib_tofolder $lib scratch/objects
    done
    #separate __wasilibc_stuff out to separate static appendage library
    mkdir -p scratch/wasilibc_objects/
    mv `grep -l __wasilibc_ scratch/objects/*` scratch/wasilibc_objects/
    # crt1.o defines _start; crt1-reactor.o defines _initialize
    # for "bare metal" scenarios neither is needed, but this does mean
    # having to arrange to call __wasm_call_ctors() oneself
    #cp -av scratch/usr/lib/wasm32-wasi/crt1-reactor.o scratch/objects/
 
    echo "-- libc prep -- " >&2
    mkdir -p scratch/libc-objects
    for lib in "${C_LIBS[@]}"; do
	unpack_library $lib
	merge_objects_fromlib_tofolder $lib scratch/libc-objects
    done
    #separate __wasilibc_stuff out to separate static appendage library
    mkdir -p scratch/libc-wasilibc_objects/
    mv `fgrep -l __wasilibc_ scratch/libc-objects/*` scratch/libc-wasilibc_objects/
    #cp -av scratch/usr/lib/wasm32-wasi/crt1-reactor.o scratch/libc-objects/

    touch scratch/unpacked.txt
)

compile_qwasi() {
    mkdir -p scratch/qwasi
    for x in ../explorations/qwasi/{noops.*.c,capture_fd_writes.c} ; do
	$CXX ${wasm32_baremetal[@]} -Wno-unused-command-line-argument -c -xc++ $x -o scratch/qwasi/$(basename $x).o
    done
    repack_library scratch/qwasi/libqwasi.a scratch/qwasi/noops.*.o
    repack_library scratch/qwasi/libqwasi-capture.a scratch/qwasi/capture_fd_writes.c.o
}

compile_qwasi
[[ "${1:-}" == "qwasi" ]] && {
    # if devtree tinkering then this updates extant staging/ outputs
    ls -l scratch/qwasi
    for x in staging/libcxx-static staging/libc-static ; do
	test ! -f $x/libqwasi.a || cp -av scratch/qwasi/libqwasi.a $x/
	test ! -f $x/libqwasi-capture.a || cp -av scratch/qwasi/libqwasi-capture.a $x/
    done
    exit 0
}

[[ "${1:-}" == "xincludes" ]] && {
    xinclude=staging/libcxx-static/xinclude
    for x in "${CXX_HEADERS[@]}" "${C_HEADERS[@]}" ; do
	test -d $xinclude/$(dirname $x) || mkdir -pv $xinclude/$(dirname $x) ;
	echo '#include <../libcxx.hpp>' > $xinclude/$x ;
    done
    exit 0
}
# false && for x in cxa.host ; do
#     echo "polyfilling $x..."
#     $CXX  ${wasm32_baremetal[@]} -Wno-unused-command-line-argument -c -xc++ src/$x.c -o scratch/objects/$x.o
#     du -hsb scratch/objects/$x.o
# done

# Create output directory
test -d staging && rm staging -rf
mkdir -p staging/libcxx-static staging/libc-static

# libcxx
repack_library staging/libcxx-static/libcxx.a scratch/objects/*
test ! -d scratch/wasilibc_objects || repack_library staging/libcxx-static/libwasi.a scratch/wasilibc_objects/*
test ! -f scratch/qwasi/libqwasi.a || cp -av scratch/qwasi/libqwasi.a staging/libcxx-static/
test ! -f scratch/qwasi/libqwasi-capture.a || cp -av scratch/qwasi/libqwasi-capture.a staging/libcxx-static/

# libc
repack_library staging/libc-static/libc.a scratch/libc-objects/*
test ! -d scratch/libc-wasilibc_objects || repack_library staging/libc-static/libwasi.a scratch/libc-wasilibc_objects/*
test ! -f scratch/qwasi/libqwasi.a || cp -av scratch/qwasi/libqwasi.a staging/libc-static/
test ! -f scratch/qwasi/libqwasi-capture.a || cp -av scratch/qwasi/libqwasi-capture.a staging/libc-static/

function make_header() {
    local mode=$1
    local ID=$2
    shift 2
    # Gather headers into a fully-preprocesed, monolithic base variation
    echo "scratch/$ID._H" >&2
    (
	echo "/* Combined headers ${#@} */"
	preprocess $mode <( amalgamate_sources "$@" ) 
    ) > scratch/$ID._H || exit 2
    
    # Construct final header file with ifguards, defines and monolithic base
    # as well as preprocessor #line entries into brief variations
    (
	echo -e "// generated"
	echo -e "#ifndef _${ID}_H\n#define _${ID}_H"
	echo "__attribute__((export_name(\".rollups.${ID}.version\"))) unsigned long long rollups_${ID}_version() { return 0x00$(date "+%Y%m%d"); }"
	cat scratch/$ID.defines || exit 40
	cat scratch/$ID._H || exit 41
	echo -e "#endif //_${ID}_H"
    )\
	| perl -pe 's@^(#[^"]+")[^ ]+wasm32-wasi/c[+][+]/v1/@$1\{libc++}/@g' \
	| perl -pe 's@^(#[^"]+")[^ ]+wasm32-wasi/@$1\{libc}/@g' \
	| perl -pe 's@^(#[^"]+")/usr/lib/[^ ]+/include/@$1\{llvm}/@g' || exit 56
}

generate_system_congruent() {
    echo "// generated"
    for x in "$@" ; do
	echo "#include <$(basename $x)>"
    done
}

generate_defines c++ "${CXX_HEADERS[@]}" "${C_HEADERS[@]}" > scratch/LIBCXX.defines
make_header c++ LIBCXX "${CXX_RESOLVED_HEADERS[@]}" "${C_RESOLVED_HEADERS[@]}" > staging/libcxx-static/libcxx-wasm32.hpp
generate_system_congruent "${CXX_RESOLVED_HEADERS[@]}"  > staging/libcxx-static/libcxx-dynamic.hpp
cp -av src/libcxx.hpp staging/libcxx-static/
cp -av test/main.cpp staging/libcxx-static/example.cpp
cp -av test/stdio.cpp staging/libcxx-static/qwasi_stdio_test.cpp

for x in nlohmann-json glm ; do
    source ../$x/_build.sh || die "error processing $x rc=$?"
done

cp -av src/libcxx.hpp staging/libcxx-static/
cp -av test/main.cpp staging/libcxx-static/example.cpp
cp -av test/stdio.cpp staging/libcxx-static/qwasi_stdio_test.cpp

generate_defines c "${C_HEADERS[@]}" > scratch/LIBC.defines
make_header c LIBC "${C_RESOLVED_HEADERS[@]}" > staging/libc-static/libc-wasm32.h
cp -av src/libc.h staging/libc-static/
generate_system_congruent "${C_RESOLVED_HEADERS[@]}" > staging/libc-static/libc-dynamic.h
cp -av test/main.c staging/libc-static/example.c
cp -av test/stdio.c staging/libc-static/qwasi_stdio_test.c

# === Generate other artifacts (licenses, etc.) ===

# pull together copyright files from the unpacked .deb's into compresed doc
amalgamate_sources $(find scratch/usr/share/doc/ -name copyright) > scratch/cxx-licenses.txt
amalgamate_sources $(find scratch/usr/share/doc/ -name copyright | grep -vE 'libc[+][+]') > scratch/c-licenses.txt
#cat scratch/licenses.txt | gzip -9 -c > staging/licenses.txt.gz
#mkdir -p staging/doc
cat scratch/cxx-licenses.txt > staging/libcxx-static/upstream-licenses.txt
cat scratch/c-licenses.txt > staging/libc-static/upstream-licenses.txt
 
# === Generate YAML-compatible readme ===
# Function to generate a YAML list from a Bash array
yaml_list() {
  local indent="$1"
  shift
  local item
  for item in "$@"; do
    echo "${indent}- ${item}"
  done
}
readmestuff=$(cat <<EOF
title: amalgamated libcxx.a and libcxx.hpp
date: $(date +%s)
GITHUB:
  REPOSITORY: ${GITHUB_REPOSITORY:-GITHUB_REPOSITORY}
  REF: ${GITHUB_REF:-GITHUB_REF}
  WORKFLOW_REF: ${GITHUB_WORKFLOW_REF:-GITHUB_WORKFLOW_REF}
llvm: $(llvm-config-$V --version)
libs: [ $(IFS=", "; echo "${CXX_LIBS[*]}") ]
headers:
  cxx:
$(yaml_list "    " "${CXX_HEADERS[@]}")
  c:
$(yaml_list "    " "${C_HEADERS[@]}")
cxxflags:
  wasm32: [ $(IFS=" "; echo "${wasm32_baremetal[*]}") ]
  link: -lcxx-static -lqwasi
  link_capture: -lcxx-static -lquasi-capture -lqwasi
misc:
  cxxpp_flags: [ $(IFS=" "; echo "${cxxpp_flags[@]}") ]
  debs:
$(for d in downloads/*.deb; do
    sha256sum "$d" | awk '{print $1}' | \
      tr -d '\n' | \
      xargs -I {} echo "    - sha256: {}"
    echo "      filename: $(basename "$d")" 
  done)
EOF
)
echo "$readmestuff" > staging/readme.txt

generate_protobins

find staging/ -ls

# === Create release tarball ===
bundle=$(date "+%Y%m%d").rollups.libcxx-wasm32.tar.gz
tar -C staging -I 'gzip -9' -cf $bundle .

echo "Build complete -- prepared artifacts are in the 'staging' directory."

ls -l $bundle

