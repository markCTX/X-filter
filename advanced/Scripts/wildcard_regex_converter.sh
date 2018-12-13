#!/bin/bash
# X-filter: A black hole for Internet advertisements
# (c) 2017 X-filter, LLC (https://x-filter.net)
# Network-wide ad blocking via your own hardware.
#
# Provides an automated migration subroutine to convert X-filter v3.x wildcard domains to X-filter v4.x regex filters
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# regexFile set in gravity.sh

wildcardFile="/etc/dnsmasq.d/03-xfilter-wildcard.conf"

convert_wildcard_to_regex() {
    if [ ! -f "${wildcardFile}" ]; then
        return
    fi
    local addrlines domains uniquedomains
    # Obtain wildcard domains from old file
    addrlines="$(grep -oE "/.*/" ${wildcardFile})"
    # Strip "/" from domain names and convert "." to regex-compatible "\."
    domains="$(sed 's/\///g;s/\./\\./g' <<< "${addrlines}")"
    # Remove repeated domains (may have been inserted two times due to A and AAAA blocking)
    uniquedomains="$(uniq <<< "${domains}")"
    # Automatically generate regex filters and remove old wildcards file
    awk '{print "(^|\\.)"$0"$"}' <<< "${uniquedomains}" >> "${regexFile:?}" && rm "${wildcardFile}"
}
