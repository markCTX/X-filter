#!/usr/bin/env bash
# X-filter: A black hole for Internet advertisements
# (c) 2017 X-filter, LLC (https://x-filter.net)
# Network-wide ad blocking via your own hardware.
#
# Switch X-filter subsystems to a different Github branch.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly X_FILTER_FILES_DIR="/etc/.xfilter"
PH_TEST="true"
source "${X_FILTER_FILES_DIR}/automated install/basic-install.sh"

# webInterfaceGitUrl set in basic-install.sh
# webInterfaceDir set in basic-install.sh
# xfilterGitURL set in basic-install.sh
# is_repo() sourced from basic-install.sh
# setupVars set in basic-install.sh
# check_download_exists sourced from basic-install.sh
# fully_fetch_repo sourced from basic-install.sh
# get_available_branches sourced from basic-install.sh
# fetch_checkout_pull_branch sourced from basic-install.sh
# checkout_pull_branch sourced from basic-install.sh

source "${setupVars}"

warning1() {
    echo "  Please note that changing branches severely alters your X-filter subsystems"
    echo "  Features that work on the master branch, may not on a development branch"
    echo -e "  ${COL_LIGHT_RED}This feature is NOT supported unless a X-filter developer explicitly asks!${COL_NC}"
    read -r -p "  Have you read and understood this? [y/N] " response
    case "${response}" in
        [yY][eE][sS]|[yY])
            echo ""
            return 0
            ;;
        *)
            echo -e "\\n  ${INFO} Branch change has been cancelled"
            return 1
            ;;
    esac
}

checkout() {
    local corebranches
    local webbranches

    # Avoid globbing
    set -f

    # This is unlikely
    if ! is_repo "${X_FILTER_FILES_DIR}" ; then
        echo -e "  ${COL_LIGHT_RED}Error: Core X-filter repo is missing from system!"
        echo -e "  Please re-run install script from https://github.com/x-filter/x-filter${COL_NC}"
        exit 1;
    fi
    if [[ "${INSTALL_WEB_INTERFACE}" == "true" ]]; then
        if ! is_repo "${webInterfaceDir}" ; then
            echo -e "  ${COL_LIGHT_RED}Error: Web Admin repo is missing from system!"
            echo -e "  Please re-run install script from https://github.com/x-filter/x-filter${COL_NC}"
            exit 1;
        fi
    fi

    if [[ -z "${1}" ]]; then
        echo -e "  ${COL_LIGHT_RED}Invalid option${COL_NC}"
        echo -e "  Try 'xfilter checkout --help' for more information."
        exit 1
    fi

    if ! warning1 ; then
        exit 1
    fi

    if [[ "${1}" == "dev" ]] ; then
        # Shortcut to check out development branches
        echo -e "  ${INFO} Shortcut \"dev\" detected - checking out development / devel branches..."
        echo ""
        echo -e "  ${INFO} X-filter Core"
        fetch_checkout_pull_branch "${X_FILTER_FILES_DIR}" "development" || { echo "  ${CROSS} Unable to pull Core developement branch"; exit 1; }
        if [[ "${INSTALL_WEB_INTERFACE}" == "true" ]]; then
            echo ""
            echo -e "  ${INFO} Web interface"
            fetch_checkout_pull_branch "${webInterfaceDir}" "devel" || { echo "  ${CROSS} Unable to pull Web development branch"; exit 1; }
        fi
        #echo -e "  ${TICK} X-filter Core"

        get_binary_name
        local path
        path="development/${binary}"
        echo "development" > /etc/xfilter/ftlbranch
    elif [[ "${1}" == "master" ]] ; then
        # Shortcut to check out master branches
        echo -e "  ${INFO} Shortcut \"master\" detected - checking out master branches..."
        echo -e "  ${INFO} X-filter core"
        fetch_checkout_pull_branch "${X_FILTER_FILES_DIR}" "master" || { echo "  ${CROSS} Unable to pull Core master branch"; exit 1; }
        if [[ ${INSTALL_WEB_INTERFACE} == "true" ]]; then
            echo -e "  ${INFO} Web interface"
            fetch_checkout_pull_branch "${webInterfaceDir}" "master" || { echo "  ${CROSS} Unable to pull Web master branch"; exit 1; }
        fi
        #echo -e "  ${TICK} Web Interface"
        get_binary_name
        local path
        path="master/${binary}"
        echo "master" > /etc/xfilter/ftlbranch
    elif [[ "${1}" == "core" ]] ; then
        str="Fetching branches from ${xfilterGitUrl}"
        echo -ne "  ${INFO} $str"
        if ! fully_fetch_repo "${X_FILTER_FILES_DIR}" ; then
            echo -e "${OVER}  ${CROSS} $str"
            exit 1
        fi
        corebranches=($(get_available_branches "${X_FILTER_FILES_DIR}"))

        if [[ "${corebranches[*]}" == *"master"* ]]; then
            echo -e "${OVER}  ${TICK} $str"
            echo -e "${INFO} ${#corebranches[@]} branches available for X-filter Core"
        else
            # Print STDERR output from get_available_branches
            echo -e "${OVER}  ${CROSS} $str\\n\\n${corebranches[*]}"
            exit 1
        fi

        echo ""
        # Have the user choose the branch they want
        if ! (for e in "${corebranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
            echo -e "  ${INFO} Requested branch \"${2}\" is not available"
            echo -e "  ${INFO} Available branches for Core are:"
            for e in "${corebranches[@]}"; do echo "      - $e"; done
            exit 1
        fi
        checkout_pull_branch "${X_FILTER_FILES_DIR}" "${2}"
    elif [[ "${1}" == "web" ]] && [[ "${INSTALL_WEB_INTERFACE}" == "true" ]] ; then
        str="Fetching branches from ${webInterfaceGitUrl}"
        echo -ne "  ${INFO} $str"
        if ! fully_fetch_repo "${webInterfaceDir}" ; then
            echo -e "${OVER}  ${CROSS} $str"
            exit 1
        fi
        webbranches=($(get_available_branches "${webInterfaceDir}"))

        if [[ "${webbranches[*]}" == *"master"* ]]; then
            echo -e "${OVER}  ${TICK} $str"
            echo -e "${INFO} ${#webbranches[@]} branches available for Web Admin"
        else
            # Print STDERR output from get_available_branches
            echo -e "${OVER}  ${CROSS} $str\\n\\n${webbranches[*]}"
            exit 1
        fi

        echo ""
        # Have the user choose the branch they want
        if ! (for e in "${webbranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
            echo -e "  ${INFO} Requested branch \"${2}\" is not available"
            echo -e "  ${INFO} Available branches for Web Admin are:"
            for e in "${webbranches[@]}"; do echo "      - $e"; done
            exit 1
        fi
        checkout_pull_branch "${webInterfaceDir}" "${2}"
    elif [[ "${1}" == "ftl" ]] ; then
        get_binary_name
        local path
        path="${2}/${binary}"

        if check_download_exists "$path"; then
            echo "  ${TICK} Branch ${2} exists"
            echo "${2}" > /etc/xfilter/ftlbranch
            FTLinstall "${binary}"
            start_service xfilter-FTL
            enable_service xfilter-FTL
        else
            echo "  ${CROSS} Requested branch \"${2}\" is not available"
            ftlbranches=( $(git ls-remote https://github.com/x-filter/ftl | grep 'heads' | sed 's/refs\/heads\///;s/ //g' | awk '{print $2}') )
            echo -e "  ${INFO} Available branches for FTL are:"
            for e in "${ftlbranches[@]}"; do echo "      - $e"; done
            exit 1
        fi

    else
        echo -e "  ${INFO} Requested option \"${1}\" is not available"
        exit 1
    fi

    # Force updating everything
    if [[  ! "${1}" == "web" && ! "${1}" == "ftl" ]]; then
        echo -e "  ${INFO} Running installer to upgrade your installation"
        if "${X_FILTER_FILES_DIR}/automated install/basic-install.sh" --unattended; then
            exit 0
        else
            echo -e "  ${COL_LIGHT_RED} Error: Unable to complete update, please contact support${COL_NC}"
            exit 1
        fi
    fi
}
