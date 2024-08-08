#!/bin/bash

# libcxx wasm32 hybrid amalgamation script that fetches prebuilt (wasm32)
# libc++.a and related .deb's from upstream ubuntu repos and amalgamates
# everything together into a singular libcxx-wasm32.a + libcxx-wasm32.hpp

set -e  # Exit on error

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
  array atomic bitset cassert chrono cerrno cstdio complex deque
  exception functional limits locale map memory stack string system_error
  type_traits vector
)
C_HEADERS=(
  string.h stdio.h stdint.h stdbool.h assert.h 
  limits.h locale.h errno.h 
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

# Build flags
wasm32_cxxflags=(
  "--target=wasm32"
  "-nostdinc"
  "-nostdlib"
  "-Wl,--no-entry"
  "-fno-exceptions"
) 

wasm32_practiceflags=(
    "${wasm32_cxxflags[@]}"
    "-isystem./staging"
    "-Wl,-L./staging"
    "-Wl,./staging/libcxx-wasm32.a"
    "-Wl,--global-base=65535"
)
test -v DEBUG && test -n $DEBUG \
    && wasm32_practiceflags+=( "-g" "-O0" ) \
    || wasm32_practiceflags+=( "-Oz" "-Wl,--strip-debug" )

if [[ "$1" == "compile" ]] ; then
    shift
    mode=$1
    shift
    $CXX -x$mode ${wasm32_practiceflags[@]} "$@"
    wasm=$(echo "$@" | grep -Eo "\b[^ ]+[.]wasm")
    test -f $wasm && wasm-dis $wasm | grep -E '[(](import|export|global) '
    exit 0
fi

cpp_isystem_dirs=( "$C_HEADERS_DIR" "$LLVM_HEADERS_DIR" )
cpp_flags=(
  "-xc"
  "${cpp_isystem_dirs[@]/#/"-isystem"}"
  "${wasm32_cxxflags[@]}"
  "-D__wasi__=1"
  "-Wno-pragma-system-header-outside-header"
  "-Wno-unused-command-line-argument"
)

cxxpp_isystem_dirs=( "$CXX_HEADERS_DIR" "${cpp_isystem_dirs[@]}" )
cxxpp_flags=(
  "-xc++"
  "${cxxpp_isystem_dirs[@]/#/"-isystem"}"
  "${wasm32_cxxflags[@]}"
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

amalgamate_sources() {( set -Euo pipefail ;
  local file
  for file in "$@"; do
    test ! -v quieters["$(basename $file).before"] || echo "${quieters[$(basename $file).before]}"
    echo "#line 0 \"$file\""
    cat "$file"
    test ! -v quieters["$(basename $file).after"] || echo "${quieters[$(basename $file).after]}"
  done
)}

amalgamate_includes() {( set -Euo pipefail ;
  local file
  for file in "$@"; do
    echo "#include <$file>"
  done
)}

function preprocess() {
    local mode=$1
    shift
    pp="$CXX ${cxxpp_flags[@]} -E -x$mode"
    [[ "$mode" == "c" ]] && pp="$CXX ${cpp_flags[@]} -E -x$mode"
    $pp "$@"
}

generate_defines() {
    local mode=$1
    shift
    echo "generate_defines $mode " >&2 
    preprocess $mode -dM /dev/null > scratch/defines_none.h
    preprocess $mode -dM <( amalgamate_includes "$@") > scratch/defines_all.h
    diff scratch/defines_none.h scratch/defines_all.h | grep -E '^>' | sed -e 's@^> @@g' \
	| ( grep -v '#define __NEED_' || true )
}

unpack_library() {( set -Euo pipefail ;
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
)}

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
    curl -s http://archive.ubuntu.com/ubuntu/dists/mantic/universe/binary-amd64/Packages.xz | xzcat \
	| grep -Eo "pool/.*${V}-dev-wasm32.*[.]deb" | sed 's@^@http://archive.ubuntu.com/ubuntu/@' \
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


# false && for x in cxa.host ; do
#     echo "polyfilling $x..."
#     $CXX  ${wasm32_cxxflags[@]} -Wno-unused-command-line-argument -c -xc++ src/$x.c -o scratch/objects/$x.o
#     du -hsb scratch/objects/$x.o
# done

# Create output directory
test -d staging && rm staging -rf
mkdir -p staging

# libcxx
repack_library staging/libcxx-wasm32.a scratch/objects/*
test -d scratch/wasilibc_objects && repack_library staging/libcxx-wasi-wasm32.a scratch/wasilibc_objects/*

# libc
repack_library staging/libc-wasm32.a scratch/libc-objects/*
test -d scratch/libc-wasilibc_objects && repack_library staging/libc-wasi-wasm32.a scratch/libc-wasilibc_objects/*

function make_header() {(set -Euo pipefail ;
    local mode=$1
    shift
    # Gather headers into a fully-preprocesed, monolithic base variation
    echo "scratch/lib$mode._H" >&2
    (
	echo '/* Combined headers */'
	preprocess $mode <( amalgamate_sources "$@" ) 
    ) > scratch/lib$mode._H
    
    # Construct final header file with ifguards, defines and monolithic base
    # as well as preprocessor #line entries into brief variations
    (
	echo -e '#ifndef _LIBCXX_H\n#define _LIBCXX_H'
	echo "__attribute__((export_name(\".rollups.lib${mode//+/x}.version\"))) unsigned long long rollups_lib${mode//+/x}_version() { return 0x00$(date "+%Y%m%d"); }"
	cat scratch/lib$mode.defines
	cat scratch/lib$mode._H 
	echo -e '#endif //_LIBCXX_H'
    ) \
	| perl -pe 's@^(#[^"]+")[^ ]+wasm32-wasi/c[+][+]/v1/@$1\{libc++}/@g' \
	| perl -pe 's@^(#[^"]+")[^ ]+wasm32-wasi/@$1\{libc}/@g' \
	| perl -pe 's@^(#[^"]+")/usr/lib/[^ ]+/include/@$1\{llvm}/@g'	       
)}

generate_defines c++ "${CXX_HEADERS[@]}" "${C_HEADERS[@]}" > scratch/libc++.defines
make_header c++ "${CXX_RESOLVED_HEADERS[@]}" "${C_RESOLVED_HEADERS[@]}" > staging/libcxx-wasm32.hpp

generate_defines c "${C_HEADERS[@]}" > scratch/libc.defines
make_header c "${C_RESOLVED_HEADERS[@]}" > staging/libc-wasm32.h

# === Generate other artifacts (licenses, etc.) ===

# pull together copyright files from the unpacked .deb's into compresed doc
amalgamate_sources $(find scratch/usr/share/doc/ -name copyright) > scratch/licenses.txt
cat scratch/licenses.txt | gzip -9 -c > staging/licenses.txt.gz

(
    echo "// generated"
    for x in "${CXX_RESOLVED_HEADERS[@]}" ; do
	echo "#include <$(basename $x)>"
    done
) > staging/libcxx-dynamic.hpp
cp -av src/libcxx.hpp staging/

(
    echo "// generated"
    for x in "${C_RESOLVED_HEADERS[@]}" ; do
	echo "#include <$(basename $x)>"
    done
) > staging/libc-dynamic.h
cp -av src/libc.h staging/

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
title: amalgamated libcxx-wasm32.a and libcxx-wasm32.hpp
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
  wasm32: [ $(IFS=" "; echo "${wasm32_cxxflags[*]}") ]
  practice: [ $(IFS=" "; echo "${wasm32_practiceflags[*]}") ] 
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
echo "$readmestuff" > staging/libcxx-wasm32.readme.txt

ls -l staging/

# === Create release tarball ===
bundle=$(date "+%Y%m%d").rollups.libcxx-wasm32.tar.gz
tar -C staging -I 'gzip -9' -cf $bundle .

echo "Build complete -- prepared artifacts are in the 'staging' directory."

ls -l $bundle

