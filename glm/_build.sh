declare -F diff_defines >/dev/null || { echo "meant to be sourced from libcxx/build.sh..." ; exit 2;  }
build_glm() {
    echo "====================================== build_glm..." >&2
    local glm=$(dirname $BASH_SOURCE)
    local version=1.0.1
    local downoad=https://github.com/g-truc/glm/releases/download/${version}/glm-${version}-light.zip
    local archive=glm-${version}-light.zip
    local -a glm_headers=(
	glm/glm.hpp
	glm/gtc/type_ptr.hpp
	glm/gtx/string_cast.hpp
    )
    local glm_defines=(
	-DGLM_ENABLE_EXPERIMENTAL
	-DGLM_FORCE_XYZW_ONLY
    )
    test -f $archive || wget -c -nc -O $archive $download
    test -d $glm/glm || unzip -q -d $glm $archive
    CXX="$CXX -I$glm/glm -isystem$glm ${glm_defines[@]}" diff_defines c++ staging/libcxx-static/libcxx-wasm32.hpp "${glm_headers[@]}" \
       > scratch/GLM.defines || die 234
    echo "====================================== build_glm -- make_header..." >&2
    {
	echo "// SOURCE: https://github.com/g-truc/glm @ ${version}"
	local -a resolved_glm_headers
	for x in ${glm_headers[@]}; do resolved_glm_headers+=($glm/$x) ; done
	# FIXME: libcxx.hpp assumed; this turns corresponding system headers into no-ops
	local yinclude=scratch/yinclude
	for x in "${CXX_HEADERS[@]}" "${C_HEADERS[@]}" ; do
	    test -d $yinclude/$(dirname $x) || mkdir -pv $yinclude/$(dirname $x) ;
	    echo "/* $x */" > $yinclude/$x ;
	done
	cxxpp_flags="" 	CXX="$CXX -P -Wno-pragma-once-outside-header ${glm_defines[@]} -isystemscratch/yinclude -I$glm/glm -I$glm/glm/gtc -I$glm/glm/gtx -isystem$glm" \
	   make_header c++ GLM "${resolved_glm_headers[@]}" || die 5
    } > staging/libcxx-static/glm.cxx
    echo "====================================== build_glm -- finalize..." >&2
    amalgamate_includes "${glm_headers[@]}" > staging/libcxx-static/glm-dynamic.hpp
    cp -av $glm/glm/copying.txt staging/libcxx-static/glm.license.txt
    cp -av $glm/test-glm.cpp staging/libcxx-static/glm.test.cpp
}

build_glm || return 5
