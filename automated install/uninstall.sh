#!/usr/bin/env bash
# X-filter: A black hole for Internet advertisements
# (c) 2017 X-filter, LLC (https://x-filter.net)
# Network-wide ad blocking via your own hardware.
#
# Completely uninstalls X-filter
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

source "/opt/xfilter/COL_TABLE"

while true; do
    read -rp "  ${QST} Are you sure you would like to remove ${COL_WHITE}X-filter${COL_NC}? [y/N] " yn
    case ${yn} in
        [Yy]* ) break;;
        [Nn]* ) echo -e "${OVER}  ${COL_LIGHT_GREEN}Uninstall has been cancelled${COL_NC}"; exit 0;;
        * ) echo -e "${OVER}  ${COL_LIGHT_GREEN}Uninstall has been cancelled${COL_NC}"; exit 0;;
    esac
done

# Must be root to uninstall
str="Root user check"
if [[ ${EUID} -eq 0 ]]; then
    echo -e "  ${TICK} ${str}"
else
    # Check if sudo is actually installed
    # If it isn't, exit because the uninstall can not complete
    if [ -x "$(command -v sudo)" ]; then
        export SUDO="sudo"
    else
        echo -e "  ${CROSS} ${str}
            Script called with non-root privileges
            The X-filter requires elevated privleges to uninstall"
        exit 1
    fi
fi

readonly X_FILTER_FILES_DIR="/etc/.xfilter"
PH_TEST="true"
source "${X_FILTER_FILES_DIR}/automated install/basic-install.sh"
# setupVars set in basic-install.sh
source "${setupVars}"

# distro_check() sourced from basic-install.sh
distro_check

# Install packages used by the X-filter
DEPS=("${INSTALLER_DEPS[@]}" "${XFILTER_DEPS[@]}")
if [[ "${INSTALL_WEB_SERVER}" == true ]]; then
    # Install the Web dependencies
    DEPS+=("${XFILTER_WEB_DEPS[@]}")
fi

# Compatability
if [ -x "$(command -v apt-get)" ]; then
    # Debian Family
    PKG_REMOVE="${PKG_MANAGER} -y remove --purge"
    package_check() {
        dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed"
    }
elif [ -x "$(command -v rpm)" ]; then
    # Fedora Family
    PKG_REMOVE="${PKG_MANAGER} remove -y"
    package_check() {
        rpm -qa | grep "^$1-" > /dev/null
    }
else
    echo -e "  ${CROSS} OS distribution not supported"
    exit 1
fi

removeAndPurge() {
    # Purge dependencies
    echo ""
    for i in "${DEPS[@]}"; do
        if package_check "${i}" > /dev/null; then
            while true; do
                read -rp "  ${QST} Do you wish to remove ${COL_WHITE}${i}${COL_NC} from your system? [Y/N] " yn
                case ${yn} in
                    [Yy]* )
                        echo -ne "  ${INFO} Removing ${i}...";
                        ${SUDO} "${PKG_REMOVE} ${i}" &> /dev/null;
                        echo -e "${OVER}  ${INFO} Removed ${i}";
                        break;;
                    [Nn]* ) echo -e "  ${INFO} Skipped ${i}"; break;;
                esac
            done
        else
            echo -e "  ${INFO} Package ${i} not installed"
        fi
    done

    # Remove dnsmasq config files
    ${SUDO} rm -f /etc/dnsmasq.conf /etc/dnsmasq.conf.orig /etc/dnsmasq.d/*-xfilter*.conf &> /dev/null
    echo -e "  ${TICK} Removing dnsmasq config files"

    # Call removeNoPurge to remove X-filter specific files
    removeNoPurge
}

removeNoPurge() {
    # Only web directories/files that are created by X-filter should be removed
    echo -ne "  ${INFO} Removing Web Interface..."
    ${SUDO} rm -rf /var/www/html/admin &> /dev/null
    ${SUDO} rm -rf /var/www/html/xfilter &> /dev/null
    ${SUDO} rm -f /var/www/html/index.lighttpd.orig &> /dev/null

    # If the web directory is empty after removing these files, then the parent html directory can be removed.
    if [ -d "/var/www/html" ]; then
        if [[ ! "$(ls -A /var/www/html)" ]]; then
            ${SUDO} rm -rf /var/www/html &> /dev/null
        fi
    fi
    echo -e "${OVER}  ${TICK} Removed Web Interface"
 
    # Attempt to preserve backwards compatibility with older versions
    # to guarantee no additional changes were made to /etc/crontab after
    # the installation of xfilter, /etc/crontab.xfilter should be permanently
    # preserved.
    if [[ -f /etc/crontab.orig ]]; then
        ${SUDO} mv /etc/crontab /etc/crontab.xfilter
        ${SUDO} mv /etc/crontab.orig /etc/crontab
        ${SUDO} service cron restart
        echo -e "  ${TICK} Restored the default system cron"
    fi

    # Attempt to preserve backwards compatibility with older versions
    if [[ -f /etc/cron.d/xfilter ]];then
        ${SUDO} rm -f /etc/cron.d/xfilter &> /dev/null
        echo -e "  ${TICK} Removed /etc/cron.d/xfilter"
    fi

    package_check lighttpd > /dev/null
    if [[ $? -eq 1 ]]; then
        ${SUDO} rm -rf /etc/lighttpd/ &> /dev/null
        echo -e "  ${TICK} Removed lighttpd"
    else
        if [ -f /etc/lighttpd/lighttpd.conf.orig ]; then
            ${SUDO} mv /etc/lighttpd/lighttpd.conf.orig /etc/lighttpd/lighttpd.conf
        fi
    fi

    ${SUDO} rm -f /etc/dnsmasq.d/adList.conf &> /dev/null
    ${SUDO} rm -f /etc/dnsmasq.d/01-xfilter.conf &> /dev/null
    ${SUDO} rm -rf /var/log/*xfilter* &> /dev/null
    ${SUDO} rm -rf /etc/xfilter/ &> /dev/null
    ${SUDO} rm -rf /etc/.xfilter/ &> /dev/null
    ${SUDO} rm -rf /opt/xfilter/ &> /dev/null
    ${SUDO} rm -f /usr/local/bin/xfilter &> /dev/null
    ${SUDO} rm -f /etc/bash_completion.d/xfilter &> /dev/null
    ${SUDO} rm -f /etc/sudoers.d/xfilter &> /dev/null
    echo -e "  ${TICK} Removed config files"

    # Restore Resolved
    if [[ -e /etc/systemd/resolved.conf.orig ]]; then
        ${SUDO} cp /etc/systemd/resolved.conf.orig /etc/systemd/resolved.conf
        systemctl reload-or-restart systemd-resolved
    fi

    # Remove FTL
    if command -v xfilter-FTL &> /dev/null; then
        echo -ne "  ${INFO} Removing xfilter-FTL..."
        if [[ -x "$(command -v systemctl)" ]]; then
            systemctl stop xfilter-FTL
        else
            service xfilter-FTL stop
        fi
        ${SUDO} rm -f /etc/init.d/xfilter-FTL
        ${SUDO} rm -f /usr/bin/xfilter-FTL
        echo -e "${OVER}  ${TICK} Removed xfilter-FTL"
    fi

    # If the xfilter manpage exists, then delete and rebuild man-db
    if [[ -f /usr/local/share/man/man8/xfilter.8 ]]; then
        ${SUDO} rm -f /usr/local/share/man/man8/xfilter.8 /usr/local/share/man/man8/xfilter-FTL.8 /usr/local/share/man/man5/xfilter-FTL.conf.5
        ${SUDO} mandb -q &>/dev/null
        echo -e "  ${TICK} Removed xfilter man page"
    fi

    # If the xfilter user exists, then remove
    if id "xfilter" &> /dev/null; then
        if ${SUDO} userdel -r xfilter 2> /dev/null; then
            echo -e "  ${TICK} Removed 'xfilter' user"
        else
            echo -e "  ${CROSS} Unable to remove 'xfilter' user"
        fi
    fi

    echo -e "\\n   We're sorry to see you go, but thanks for checking out X-filter!
       If you need help, reach out to us on Github, Discourse, Reddit or Twitter
       Reinstall at any time: ${COL_WHITE}curl -sSL https://install.x-filter.net | bash${COL_NC}

      ${COL_LIGHT_RED}Please reset the DNS on your router/clients to restore internet connectivity
      ${COL_LIGHT_GREEN}Uninstallation Complete! ${COL_NC}"
}

######### SCRIPT ###########
if command -v vcgencmd &> /dev/null; then
    echo -e "  ${INFO} All dependencies are safe to remove on Raspbian"
else
    echo -e "  ${INFO} Be sure to confirm if any dependencies should not be removed"
fi
while true; do
    echo -e "  ${INFO} ${COL_YELLOW}The following dependencies may have been added by the X-filter install:"
    echo -n "    "
    for i in "${DEPS[@]}"; do
        echo -n "${i} "
    done
    echo "${COL_NC}"
    read -rp "  ${QST} Do you wish to go through each dependency for removal? (Choosing No will leave all dependencies installed) [Y/n] " yn
    case ${yn} in
        [Yy]* ) removeAndPurge; break;;
        [Nn]* ) removeNoPurge; break;;
        * ) removeAndPurge; break;;
    esac
done
