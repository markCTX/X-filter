#!/usr/bin/env bash
# X-filter: A black hole for Internet advertisements
# (c) 2017 X-filter, LLC (https://x-filter.net)
# Network-wide ad blocking via your own hardware.
#
# Show version numbers
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Variables
DEFAULT="-1"
COREGITDIR="/etc/.xfilter/"
WEBGITDIR="/var/www/html/admin/"

getLocalVersion() {
    # FTL requires a different method
    if [[ "$1" == "FTL" ]]; then
        xfilter-FTL version
        return 0
    fi

    # Get the tagged version of the local repository
    local directory="${1}"
    local version

    cd "${directory}" 2> /dev/null || { echo "${DEFAULT}"; return 1; }
    version=$(git describe --tags --always || echo "$DEFAULT")
    if [[ "${version}" =~ ^v ]]; then
        echo "${version}"
    elif [[ "${version}" == "${DEFAULT}" ]]; then
        echo "ERROR"
        return 1
    else
        echo "Untagged"
    fi
    return 0
}

getLocalHash() {
    # Local FTL hash does not exist on filesystem
    if [[ "$1" == "FTL" ]]; then
        echo "N/A"
        return 0
    fi

    # Get the short hash of the local repository
    local directory="${1}"
    local hash

    cd "${directory}" 2> /dev/null || { echo "${DEFAULT}"; return 1; }
    hash=$(git rev-parse --short HEAD || echo "$DEFAULT")
    if [[ "${hash}" == "${DEFAULT}" ]]; then
        echo "ERROR"
        return 1
    else
        echo "${hash}"
    fi
    return 0
}

getRemoteHash(){
    # Remote FTL hash is not applicable
    if [[ "$1" == "FTL" ]]; then
        echo "N/A"
        return 0
    fi

    local daemon="${1}"
    local branch="${2}"

    hash=$(git ls-remote --heads "https://github.com/x-filter/${daemon}" | \
        awk -v bra="$branch" '$0~bra {print substr($0,0,8);exit}')
    if [[ -n "$hash" ]]; then
        echo "$hash"
    else
        echo "ERROR"
        return 1
    fi
    return 0
}

getRemoteVersion(){
    # Get the version from the remote origin
    local daemon="${1}"
    local version

    version=$(curl --silent --fail "https://api.github.com/repos/x-filter/${daemon}/releases/latest" | \
        awk -F: '$1 ~/tag_name/ { print $2 }' | \
        tr -cd '[[:alnum:]]._-')
    if [[ "${version}" =~ ^v ]]; then
        echo "${version}"
    else
        echo "ERROR"
        return 1
    fi
    return 0
}

versionOutput() {
    [[ "$1" == "x-filter" ]] && GITDIR=$COREGITDIR
    [[ "$1" == "AdminLTE" ]] && GITDIR=$WEBGITDIR
    [[ "$1" == "FTL" ]] && GITDIR="FTL"

    [[ "$2" == "-c" ]] || [[ "$2" == "--current" ]] || [[ -z "$2" ]] && current=$(getLocalVersion $GITDIR)
    [[ "$2" == "-l" ]] || [[ "$2" == "--latest" ]] || [[ -z "$2" ]] && latest=$(getRemoteVersion "$1")
    if [[ "$2" == "-h" ]] || [[ "$2" == "--hash" ]]; then
        [[ "$3" == "-c" ]] || [[ "$3" == "--current" ]] || [[ -z "$3" ]] && curHash=$(getLocalHash "$GITDIR")
        [[ "$3" == "-l" ]] || [[ "$3" == "--latest" ]] || [[ -z "$3" ]] && latHash=$(getRemoteHash "$1" "$(cd "$GITDIR" 2> /dev/null && git rev-parse --abbrev-ref HEAD)")
    fi

    if [[ -n "$current" ]] && [[ -n "$latest" ]]; then
        output="${1^} version is $current (Latest: $latest)"
    elif [[ -n "$current" ]] && [[ -z "$latest" ]]; then
        output="Current ${1^} version is $current"
    elif [[ -z "$current" ]] && [[ -n "$latest" ]]; then
        output="Latest ${1^} version is $latest"
    elif [[ "$curHash" == "N/A" ]] || [[ "$latHash" == "N/A" ]]; then
        output="${1^} hash is not applicable"
    elif [[ -n "$curHash" ]] && [[ -n "$latHash" ]]; then
        output="${1^} hash is $curHash (Latest: $latHash)"
    elif [[ -n "$curHash" ]] && [[ -z "$latHash" ]]; then
        output="Current ${1^} hash is $curHash"
    elif [[ -z "$curHash" ]] && [[ -n "$latHash" ]]; then
        output="Latest ${1^} hash is $latHash"
    else
        errorOutput
    fi

    [[ -n "$output" ]] && echo "  $output"
}

errorOutput() {
    echo "  Invalid Option! Try 'xfilter -v --help' for more information."
    exit 1
}

defaultOutput() {
    versionOutput "x-filter" "$@"
    versionOutput "AdminLTE" "$@"
    versionOutput "FTL" "$@"
}

helpFunc() {
    echo "Usage: xfilter -v [repo | option] [option]
Example: 'xfilter -v -p -l'
Show X-filter, Admin Console & FTL versions

Repositories:
  -p, --xfilter         Only retrieve info regarding X-filter repository
  -a, --admin          Only retrieve info regarding AdminLTE repository
  -f, --ftl            Only retrieve info regarding FTL repository

Options:
  -c, --current        Return the current version
  -l, --latest         Return the latest version
  --hash               Return the Github hash from your local repositories
  -h, --help           Show this help dialog"
  exit 0
}

case "${1}" in
    "-p" | "--xfilter"    ) shift; versionOutput "x-filter" "$@";;
    "-a" | "--admin"     ) shift; versionOutput "AdminLTE" "$@";;
    "-f" | "--ftl"       ) shift; versionOutput "FTL" "$@";;
    "-h" | "--help"      ) helpFunc;;
    *                    ) defaultOutput "$@";;
esac
