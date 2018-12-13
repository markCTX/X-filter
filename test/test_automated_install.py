from textwrap import dedent
import re
from conftest import (
    SETUPVARS,
    tick_box,
    info_box,
    cross_box,
    mock_command,
    mock_command_2,
    run_script
)


def test_supported_operating_system(Xfilter):
    '''
    confirm installer exists on unsupported distribution
    '''
    # break supported package managers to emulate an unsupported distribution
    Xfilter.run('rm -rf /usr/bin/apt-get')
    Xfilter.run('rm -rf /usr/bin/rpm')
    distro_check = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    distro_check
    ''')
    expected_stdout = cross_box + ' OS distribution not supported'
    assert expected_stdout in distro_check.stdout
    # assert distro_check.rc == 1


def test_setupVars_are_sourced_to_global_scope(Xfilter):
    '''
    currently update_dialogs sources setupVars with a dot,
    then various other functions use the variables.
    This confirms the sourced variables are in scope between functions
    '''
    setup_var_file = 'cat <<EOF> /etc/xfilter/setupVars.conf\n'
    for k, v in SETUPVARS.iteritems():
        setup_var_file += "{}={}\n".format(k, v)
    setup_var_file += "EOF\n"
    Xfilter.run(setup_var_file)

    script = dedent('''\
    set -e
    printSetupVars() {
        # Currently debug test function only
        echo "Outputting sourced variables"
        echo "XFILTER_INTERFACE=${XFILTER_INTERFACE}"
        echo "IPV4_ADDRESS=${IPV4_ADDRESS}"
        echo "IPV6_ADDRESS=${IPV6_ADDRESS}"
        echo "XFILTER_DNS_1=${XFILTER_DNS_1}"
        echo "XFILTER_DNS_2=${XFILTER_DNS_2}"
    }
    update_dialogs() {
        . /etc/xfilter/setupVars.conf
    }
    update_dialogs
    printSetupVars
    ''')

    output = run_script(Xfilter, script).stdout

    for k, v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output


def test_setupVars_saved_to_file(Xfilter):
    '''
    confirm saved settings are written to a file for future updates to re-use
    '''
    # dedent works better with this and padding matching script below
    set_setup_vars = '\n'
    for k, v in SETUPVARS.iteritems():
        set_setup_vars += "    {}={}\n".format(k, v)
    Xfilter.run(set_setup_vars).stdout

    script = dedent('''\
    set -e
    echo start
    TERM=xterm
    source /opt/xfilter/basic-install.sh
    {}
    mkdir -p /etc/dnsmasq.d
    version_check_dnsmasq
    echo "" > /etc/xfilter/xfilter-FTL.conf
    finalExports
    cat /etc/xfilter/setupVars.conf
    '''.format(set_setup_vars))

    output = run_script(Xfilter, script).stdout

    for k, v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output


def test_configureFirewall_firewalld_running_no_errors(Xfilter):
    '''
    confirms firewalld rules are applied when firewallD is running
    '''
    # firewallD returns 'running' as status
    mock_command('firewall-cmd', {'*': ('running', 0)}, Xfilter)
    # Whiptail dialog returns Ok for user prompt
    mock_command('whiptail', {'*': ('', 0)}, Xfilter)
    configureFirewall = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Configuring FirewallD for httpd and xfilter-FTL'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Xfilter.run('cat /var/log/firewall-cmd').stdout
    assert 'firewall-cmd --state' in firewall_calls
    assert ('firewall-cmd '
            '--permanent '
            '--add-service=http '
            '--add-service=dns') in firewall_calls
    assert 'firewall-cmd --reload' in firewall_calls


def test_configureFirewall_firewalld_disabled_no_errors(Xfilter):
    '''
    confirms firewalld rules are not applied when firewallD is not running
    '''
    # firewallD returns non-running status
    mock_command('firewall-cmd', {'*': ('not running', '1')}, Xfilter)
    configureFirewall = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = ('No active firewall detected.. '
                       'skipping firewall configuration')
    assert expected_stdout in configureFirewall.stdout


def test_configureFirewall_firewalld_enabled_declined_no_errors(Xfilter):
    '''
    confirms firewalld rules are not applied when firewallD is running, user
    declines ruleset
    '''
    # firewallD returns running status
    mock_command('firewall-cmd', {'*': ('running', 0)}, Xfilter)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', 1)}, Xfilter)
    configureFirewall = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Not installing firewall rulesets.'
    assert expected_stdout in configureFirewall.stdout


def test_configureFirewall_no_firewall(Xfilter):
    ''' confirms firewall skipped no daemon is running '''
    configureFirewall = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'No active firewall detected'
    assert expected_stdout in configureFirewall.stdout


def test_configureFirewall_IPTables_enabled_declined_no_errors(Xfilter):
    '''
    confirms IPTables rules are not applied when IPTables is running, user
    declines ruleset
    '''
    # iptables command exists
    mock_command('iptables', {'*': ('', '0')}, Xfilter)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*': ('', '0')}, Xfilter)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, Xfilter)
    configureFirewall = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Not installing firewall rulesets.'
    assert expected_stdout in configureFirewall.stdout


def test_configureFirewall_IPTables_enabled_rules_exist_no_errors(Xfilter):
    '''
    confirms IPTables rules are not applied when IPTables is running and rules
    exist
    '''
    # iptables command exists and returns 0 on calls
    # (should return 0 on iptables -C)
    mock_command('iptables', {'-S': ('-P INPUT DENY', '0')}, Xfilter)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*': ('', '0')}, Xfilter)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Xfilter)
    configureFirewall = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Installing new IPTables firewall rulesets'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Xfilter.run('cat /var/log/iptables').stdout
    # General call type occurances
    assert len(re.findall(r'iptables -S', firewall_calls)) == 1
    assert len(re.findall(r'iptables -C', firewall_calls)) == 4
    assert len(re.findall(r'iptables -I', firewall_calls)) == 0

    # Specific port call occurances
    assert len(re.findall(r'tcp --dport 80', firewall_calls)) == 1
    assert len(re.findall(r'tcp --dport 53', firewall_calls)) == 1
    assert len(re.findall(r'udp --dport 53', firewall_calls)) == 1
    assert len(re.findall(r'tcp --dport 4711:4720', firewall_calls)) == 1


def test_configureFirewall_IPTables_enabled_not_exist_no_errors(Xfilter):
    '''
    confirms IPTables rules are applied when IPTables is running and rules do
    not exist
    '''
    # iptables command and returns 0 on calls (should return 1 on iptables -C)
    mock_command(
        'iptables',
        {
            '-S': (
                '-P INPUT DENY',
                '0'
            ),
            '-C': (
                '',
                1
            ),
            '-I': (
                '',
                0
            )
        },
        Xfilter
    )
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*': ('', '0')}, Xfilter)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Xfilter)
    configureFirewall = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Installing new IPTables firewall rulesets'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Xfilter.run('cat /var/log/iptables').stdout
    # General call type occurances
    assert len(re.findall(r'iptables -S', firewall_calls)) == 1
    assert len(re.findall(r'iptables -C', firewall_calls)) == 4
    assert len(re.findall(r'iptables -I', firewall_calls)) == 4

    # Specific port call occurances
    assert len(re.findall(r'tcp --dport 80', firewall_calls)) == 2
    assert len(re.findall(r'tcp --dport 53', firewall_calls)) == 2
    assert len(re.findall(r'udp --dport 53', firewall_calls)) == 2
    assert len(re.findall(r'tcp --dport 4711:4720', firewall_calls)) == 2


def test_selinux_enforcing_default_exit(Xfilter):
    '''
    confirms installer prompts to exit when SELinux is Enforcing by default
    '''
    # getenforce returns the running state of SELinux
    mock_command('getenforce', {'*': ('Enforcing', '0')}, Xfilter)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, Xfilter)
    check_selinux = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux mode detected: Enforcing'
    assert expected_stdout in check_selinux.stdout
    expected_stdout = 'SELinux Enforcing detected, exiting installer'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 1


def test_selinux_enforcing_continue(Xfilter):
    '''
    confirms installer prompts to continue with custom policy warning
    '''
    # getenforce returns the running state of SELinux
    mock_command('getenforce', {'*': ('Enforcing', '0')}, Xfilter)
    # Whiptail dialog returns Continue for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Xfilter)
    check_selinux = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux mode detected: Enforcing'
    assert expected_stdout in check_selinux.stdout
    expected_stdout = info_box + (' Continuing installation with SELinux '
                                  'Enforcing')
    assert expected_stdout in check_selinux.stdout
    expected_stdout = info_box + (' Please refer to official SELinux '
                                  'documentation to create a custom policy')
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


def test_selinux_permissive(Xfilter):
    '''
    confirms installer continues when SELinux is Permissive
    '''
    # getenforce returns the running state of SELinux
    mock_command('getenforce', {'*': ('Permissive', '0')}, Xfilter)
    check_selinux = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux mode detected: Permissive'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


def test_selinux_disabled(Xfilter):
    '''
    confirms installer continues when SELinux is Disabled
    '''
    mock_command('getenforce', {'*': ('Disabled', '0')}, Xfilter)
    check_selinux = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux mode detected: Disabled'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


def test_installXfilterWeb_fresh_install_no_errors(Xfilter):
    '''
    confirms all web page assets from Core repo are installed on a fresh build
    '''
    installWeb = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    installXfilterWeb
    ''')
    expected_stdout = info_box + ' Installing blocking page...'
    assert expected_stdout in installWeb.stdout
    expected_stdout = tick_box + (' Creating directory for blocking page, '
                                  'and copying files')
    assert expected_stdout in installWeb.stdout
    expected_stdout = cross_box + ' Backing up index.lighttpd.html'
    assert expected_stdout in installWeb.stdout
    expected_stdout = ('No default index.lighttpd.html file found... '
                       'not backing up')
    assert expected_stdout in installWeb.stdout
    expected_stdout = tick_box + ' Installing sudoer file'
    assert expected_stdout in installWeb.stdout
    web_directory = Xfilter.run('ls -r /var/www/html/xfilter').stdout
    assert 'index.php' in web_directory
    assert 'blockingpage.css' in web_directory


def test_update_package_cache_success_no_errors(Xfilter):
    '''
    confirms package cache was updated without any errors
    '''
    updateCache = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    distro_check
    update_package_cache
    ''')
    expected_stdout = tick_box + ' Update local cache of available packages'
    assert expected_stdout in updateCache.stdout
    assert 'error' not in updateCache.stdout.lower()


def test_update_package_cache_failure_no_errors(Xfilter):
    '''
    confirms package cache was not updated
    '''
    mock_command('apt-get', {'update': ('', '1')}, Xfilter)
    updateCache = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    distro_check
    update_package_cache
    ''')
    expected_stdout = cross_box + ' Update local cache of available packages'
    assert expected_stdout in updateCache.stdout
    assert 'Error: Unable to update package cache.' in updateCache.stdout


def test_FTL_detect_aarch64_no_errors(Xfilter):
    '''
    confirms only aarch64 package is downloaded for FTL engine
    '''
    # mock uname to return aarch64 platform
    mock_command('uname', {'-m': ('aarch64', '0')}, Xfilter)
    # mock ldd to respond with aarch64 shared library
    mock_command(
        'ldd',
        {
            '/bin/ls': (
                '/lib/ld-linux-aarch64.so.1',
                '0'
            )
        },
        Xfilter
    )
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected ARM-aarch64 architecture'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv6l_no_errors(Xfilter):
    '''
    confirms only armv6l package is downloaded for FTL engine
    '''
    # mock uname to return armv6l platform
    mock_command('uname', {'-m': ('armv6l', '0')}, Xfilter)
    # mock ldd to respond with aarch64 shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux-armhf.so.3', '0')}, Xfilter)
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (' Detected ARM-hf architecture '
                                  '(armv6 or lower)')
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv7l_no_errors(Xfilter):
    '''
    confirms only armv7l package is downloaded for FTL engine
    '''
    # mock uname to return armv7l platform
    mock_command('uname', {'-m': ('armv7l', '0')}, Xfilter)
    # mock ldd to respond with aarch64 shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux-armhf.so.3', '0')}, Xfilter)
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected ARM-hf architecture (armv7+)'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_x86_64_no_errors(Xfilter):
    '''
    confirms only x86_64 package is downloaded for FTL engine
    '''
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected x86_64 architecture'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_unknown_no_errors(Xfilter):
    ''' confirms only generic package is downloaded for FTL engine '''
    # mock uname to return generic platform
    mock_command('uname', {'-m': ('mips', '0')}, Xfilter)
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = 'Not able to detect architecture (unknown: mips)'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_download_aarch64_no_errors(Xfilter):
    '''
    confirms only aarch64 package is downloaded for FTL engine
    '''
    # mock uname to return generic platform
    download_binary = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    FTLinstall xfilter-FTL-aarch64-linux-gnu
    ''')
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in download_binary.stdout
    assert 'error' not in download_binary.stdout.lower()


def test_FTL_download_unknown_fails_no_errors(Xfilter):
    '''
    confirms unknown binary is not downloaded for FTL engine
    '''
    # mock uname to return generic platform
    download_binary = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    FTLinstall xfilter-FTL-mips
    ''')
    expected_stdout = cross_box + ' Downloading and Installing FTL'
    assert expected_stdout in download_binary.stdout
    error1 = 'Error: URL https://github.com/x-filter/FTL/releases/download/'
    assert error1 in download_binary.stdout
    error2 = 'not found'
    assert error2 in download_binary.stdout


def test_FTL_binary_installed_and_responsive_no_errors(Xfilter):
    '''
    confirms FTL binary is copied and functional in installed location
    '''
    installed_binary = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    FTLdetect
    xfilter-FTL version
    ''')
    expected_stdout = 'v'
    assert expected_stdout in installed_binary.stdout


# def test_FTL_support_files_installed(Xfilter):
#     '''
#     confirms FTL support files are installed
#     '''
#     support_files = Xfilter.run('''
#     source /opt/xfilter/basic-install.sh
#     FTLdetect
#     stat -c '%a %n' /var/log/xfilter-FTL.log
#     stat -c '%a %n' /run/xfilter-FTL.port
#     stat -c '%a %n' /run/xfilter-FTL.pid
#     ls -lac /run
#     ''')
#     assert '644 /run/xfilter-FTL.port' in support_files.stdout
#     assert '644 /run/xfilter-FTL.pid' in support_files.stdout
#     assert '644 /var/log/xfilter-FTL.log' in support_files.stdout


def test_IPv6_only_link_local(Xfilter):
    '''
    confirms IPv6 blocking is disabled for Link-local address
    '''
    # mock ip -6 address to return Link-local address
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 fe80::d210:52fa:fe00:7ad7/64 scope link',
                '0'
            )
        },
        Xfilter
    )
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = ('Unable to find IPv6 ULA/GUA address, '
                       'IPv6 adblocking will not be enabled')
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_only_ULA(Xfilter):
    '''
    confirms IPv6 blocking is enabled for ULA addresses
    '''
    # mock ip -6 address to return ULA address
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global',
                '0'
            )
        },
        Xfilter
    )
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_only_GUA(Xfilter):
    '''
    confirms IPv6 blocking is enabled for GUA addresses
    '''
    # mock ip -6 address to return GUA address
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global',
                '0'
            )
        },
        Xfilter
    )
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 GUA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_GUA_ULA_test(Xfilter):
    '''
    confirms IPv6 blocking is enabled for GUA and ULA addresses
    '''
    # mock ip -6 address to return GUA and ULA addresses
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global\n'
                'inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global',
                '0'
            )
        },
        Xfilter
    )
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_ULA_GUA_test(Xfilter):
    '''
    confirms IPv6 blocking is enabled for GUA and ULA addresses
    '''
    # mock ip -6 address to return ULA and GUA addresses
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global\n'
                'inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global',
                '0'
            )
        },
        Xfilter
    )
    detectPlatform = Xfilter.run('''
    source /opt/xfilter/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout
