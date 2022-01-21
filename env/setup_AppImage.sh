#! /bin/bash

main () {
    local OPTIND=1 option quiet
    while getopts "q" option
    do
    case "${option}"
    in
        q) quiet=true;;
    esac
    done

    local prefix="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
    # add to env variable define root pf package
    export GRAND_ROOT=$prefix
    local tag="$(basename ${prefix})"
    logmsg () {
        [[ -z "${quiet}" ]] && echo "[${tag}] $@"
    }

    local ARCH="x86_64"
    if [ ! -e "${prefix}/bin/python3-${ARCH}.AppDir" ]; then
        logmsg "--Fetching AppImage"
        local url="https://github.com/grand-mother/grand/releases/download/appimage/python3-${ARCH}.AppImage"
        (cd "${prefix}/bin" && wget -cq "${url}")
        if [ "$?" != "0" ]; then
            logmsg "  could not fetch ${url}"
            return 1
        fi
        chmod u+x "${prefix}/bin/python3-${ARCH}.AppImage"
        logmsg "  AppImage retrieved"

        logmsg "--Extracting AppImage"
        (cd "${prefix}/bin" && \
         ./python3-${ARCH}.AppImage --appimage-extract &> /dev/null && \
         mv "squashfs-root" "python3-${ARCH}.AppDir" &&
         rm -f "python3-${ARCH}.AppImage")
        logmsg "  AppImage extracted"

        if [ -f "${prefix}/lib/python/grand/_core.so" ]; then
            logmsg "--Cleaning existing install"
            make clean
        fi
    fi

    VERSION=$(${prefix}/bin/python3-${ARCH}.AppDir/AppRun -c 'import sys; print(".".join([str(v) for v in sys.version_info[:2]]))')

    if [ ! -d "${prefix}/user/grand" ]; then
        mkdir -p "${prefix}/user/grand"
    fi

    logmsg "--Setting the environment"

    # Expand the PATH
    expand_path () {
        local path="${prefix}/${1}"
        if [[ ! "$PATH" =~ "${path}" ]]; then
            logmsg "  Adding \$PREFIX/${1} to PATH"
            export PATH="${path}:${PATH}"
        fi
    }

    expand_path "bin"
    expand_path "user/grand/.local/bin"
    # add in PATH executable install by pip (like pylint)
    expand_path "bin/python3-x86_64.AppDir/opt/python3.8/bin"
    # add in PATH quality for script
    expand_path "quality"

    expand_pythonpath () {
        local path="${prefix}/${1}"
        if [[ ! "$PYTHONPATH" =~ "${path}" ]]; then
            logmsg "  Adding \$PREFIX/${1} to PYTHONPATH"
            export PYTHONPATH="${path}:${PYTHONPATH}"
        fi
    }

    expand_pythonpath "lib/python${VERSION}"

    local target="${prefix}/lib/python${VERSION}"
    local link
    for link in $(ls -d "${prefix}/lib/python"* 2>/dev/null)
    do
        [[ "${link}" != "${target}" ]] && rm -rf "${link}"
    done
    mkdir -p "${target}"
    [ ! -L "${target}/grand" ] && ln -s "../../grand" "${target}/grand"

    # Rebase the shebangs of Python scripts
    sanitize_shebangs () {
        local exe
        for exe in $(ls -d "${prefix}/${2}/"* 2>/dev/null)
        do
            [ -d "${exe}" ] && continue
            if [ "$(sed -n '/^#!.*\/python.*/p;q' ${exe})" ]; then
                local name=$(basename "${exe}")
                logmsg "  Sanitizing ${1}::$name"
                sed -i '1s|^#!.*\/python.*|#!/usr/bin/env python|' "$exe"
            fi
        done
    }

    sanitize_shebangs "system" "bin"
    sanitize_shebangs "user" "user/grand/.local/bin"

    # Build the C extensions
    build_c () {
        logmsg "--Installing C modules & libraries"
        local tmpfile=$(mktemp /tmp/grand-setup-build.XXXXXX)
        $(make install >& "${tmpfile}")
        if [ "$?" != "0" ]; then
            cat "${tmpfile}"
            rm -f -- "${tmpfile}"
            logmsg ""
            logmsg "An unexpected error occured. See details above."
            logmsg "The reason might be that your Python AppImage is out of date"
            logmsg "  Try \`rm bin/python3-*.\` and re-source this script"
            logmsg "  If this error persists please open an issue at:"
            logmsg "    https://github.com/grand-mother/grand/issues"
            return 1
        else
            rm -f -- "${tmpfile}"
        fi
    }

    if [ ! -f "${prefix}/lib/python/grand/_core.so" ]; then
        build_c
    fi

    logmsg "--Environment set"
}


main "$@"
unset -f expand_path logmsg main sanitize_shebangs
