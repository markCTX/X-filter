#!/usr/bin/env bash
# X-filter: A black hole for Internet advertisements
# (c) 2017 X-filter, LLC (https://x-filter.net)
# Network-wide ad blocking via your own hardware.
#
# Flushes X-filter's log file
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

colfile="/opt/xfilter/COL_TABLE"
source ${colfile}

# Determine database location
# Obtain DBFILE=... setting from xfilter-FTL.db
# Constructed to return nothing when
# a) the setting is not present in the config file, or
# b) the setting is commented out (e.g. "#DBFILE=...")
FTLconf="/etc/xfilter/xfilter-FTL.conf"
if [ -e "$FTLconf" ]; then
    DBFILE="$(sed -n -e 's/^\s*DBFILE\s*=\s*//p' ${FTLconf})"
fi
# Test for empty string. Use standard path in this case.
if [ -z "$DBFILE" ]; then
    DBFILE="/etc/xfilter/xfilter-FTL.db"
fi

if [[ "$@" != *"quiet"* ]]; then
    echo -ne "  ${INFO} Flushing /var/log/xfilter.log ..."
fi
if [[ "$@" == *"once"* ]]; then
    # Nightly logrotation
    if command -v /usr/sbin/logrotate >/dev/null; then
        # Logrotate once
        /usr/sbin/logrotate --force /etc/xfilter/logrotate
    else
        # Copy xfilter.log over to xfilter.log.1
        # and empty out xfilter.log
        # Note that moving the file is not an option, as
        # dnsmasq would happily continue writing into the
        # moved file (it will have the same file handler)
        cp /var/log/xfilter.log /var/log/xfilter.log.1
        echo " " > /var/log/xfilter.log
    fi
else
    # Manual flushing
    if command -v /usr/sbin/logrotate >/dev/null; then
        # Logrotate twice to move all data out of sight of FTL
        /usr/sbin/logrotate --force /etc/xfilter/logrotate; sleep 3
        /usr/sbin/logrotate --force /etc/xfilter/logrotate
    else
        # Flush both xfilter.log and xfilter.log.1 (if existing)
        echo " " > /var/log/xfilter.log
        if [ -f /var/log/xfilter.log.1 ]; then
            echo " " > /var/log/xfilter.log.1
        fi
    fi
    # Delete most recent 24 hours from FTL's database, leave even older data intact (don't wipe out all history)
    deleted=$(sqlite3 "${DBFILE}" "DELETE FROM queries WHERE timestamp >= strftime('%s','now')-86400; select changes() from queries limit 1")

    # Restart xfilter-FTL to force reloading history
    sudo xfilter restartdns
fi

if [[ "$@" != *"quiet"* ]]; then
    echo -e "${OVER}  ${TICK} Flushed /var/log/xfilter.log"
    echo -e "  ${TICK} Deleted ${deleted} queries from database"
fi
