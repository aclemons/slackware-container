#!/bin/bash

# _is_sourced tests whether this script is being source, or executed directly
_is_sourced() {
  # https://unix.stackexchange.com/a/215279
  # thanks @tianon
  [ "${FUNCNAME[${#FUNCNAME[@]} - 1]}" == 'source' ]
}

_usage() {
    echo "... just read the code"
}

_fetch_file_list() {
    local mirror="${1}"
    local release="${2}"
    local ret

    curl -sSL "${mirror}/${release}/FILELIST.TXT"
    ret=$?
    if [ $ret -ne 0 ] ; then
        return $ret
    fi
}

main() {
    local mirror
    local release
    local tmp_file_list
    local ret

    mirror="${MIRROR:-http://slackware.osuosl.org}"
    release="${RELEASE:-slackware64-current}"

    while getopts ":hm:r:tpe" opts ; do
        case "${opts}" in
            m)
                mirror="${OPTARG}"
                ;;
            r)
                release="${OPTARG}"
                ;;
            *)
                _usage
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    tmp_dir="$(mktemp -d)"
    tmp_file_list="${tmp_dir}/FILELIST.TXT"
    _fetch_file_list "${mirror}" "${release}" > "${tmp_file_list}"
    ret=$?
    if [ $ret -ne 0 ] ; then
        echo "ERROR fetching FILELIST.TXT" >&2
        exit $ret
    fi

    grep '\.t.z$' "${tmp_file_list}" | awk '{ print $(NF) }' | sed -e 's|\./\(.*\.t.z\)$|\1|g'
}

_is_sourced || main "${@}"

# vim:set shiftwidth=4 softtabstop=4 expandtab:
