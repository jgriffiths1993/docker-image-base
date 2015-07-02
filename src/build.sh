#!/bin/bash
set -x
set -e

# Constant Variables & potentially changing options
BUILD_DIR="/build"
OS_FLAVOUR=""
OS_MAJOR=""
OS_MINOR=""
OS_CODENAME=""
EPEL_5="http://www.mirrorservice.org/sites/dl.fedoraproject.org/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm"
EPEL_6="http://www.mirrorservice.org/sites/dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm"
EPEL_7="http://www.mirrorservice.org/sites/dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm"
RUNIT_EL_REPO="https://packagecloud.io/install/repositories/imeyer/runit/script.rpm"
RUNIT_SUSE_REPO="ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/openSUSE:/infrastructure:/devel/SLE_11/x86_64/runit-2.1.1-2.1.x86_64.rpm"
SLES_NCC_USERNAME=""
SLES_NCC_PASSWORD=""

function main()
{
    identify
    prepare
    add_repositories
    upgrade_packages
    install_dependencies
    add_config
    install_pidone
    install_runit
    add_user "jenkins" "jenkins"
    add_runit_config
    generate_host_keys
    polish
    cleanup
}

function identify()
{
    # Identify distributions WITHOUT using LSB
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
        OS_FLAVOUR="$ID"
        OS_VERSION="$VERSION_ID"
    elif [ -f "/etc/redhat-release" ]; then
        local rhel_str="$(cat /etc/redhat-release | sed 's/^\([a-zA-Z]\+\).*release\s\+\([0-9]\+\)\..*$/\1 \2/')"
        local os_prefix="$(echo $rhel_str | cut -d' ' -f1)"
        if [[ $os_prefix == "Red" ]]; then
            OS_FLAVOUR="rhel"
        elif [[ $os_prefix == "CentOS" ]]; then
            OS_FLAVOUR="centos"
        fi
        OS_VERSION="$(echo $rhel_str | cut -d' ' -f2)"
    elif [ -f "/etc/SuSE-release" ]; then
        if grep 'Enterprise Server' /etc/SuSE-release; then
            OS_FLAVOUR="sles"
        else
            OS_FLAVOUR="suse"
        fi
        OS_VERSION="$(cat /etc/SuSE-release | grep 'VERSION' | awk '{print$3}')"
    elif [ -f "/etc/debian_version" ] && grep 'debian' /etc/apt/sources.list; then
        OS_FLAVOUR="debian"
        OS_VERSION="$(cat /etc/debian_version | cut -d'.' -f1)"
    else
        echo "Unknown OS - cannot get OS flavour and version."
        exit 1
    fi
}

function prepare() 
{
    export HOME="/root"
    export INITRD="no"
    ln -sf /bin/true /usr/sbin/ischroot
    ln -sf /bin/true /sbin/initctl
    ln -sf /bin/true /dev/initctl
    case "$OS_FLAVOUR" in
        ubuntu|debian)
            export DEBIAN_FRONTEND="noninteractive"
            rm -vf /usr/sbin/policy-rc.d
            ;;
        suse|sles)
            # SuSE doesn't like vendor changes for upgrading dependent packages
            if ! egrep '^\s*solver.allowVendorChange' /etc/zypp/zypp.conf; then
                echo "solver.allowVendorChange=true" >> /etc/zypp/zypp.conf
            fi
            ;;
    esac
}

function add_repositories()
{
    case "$OS_FLAVOUR" in
        debian|ubuntu) # Shouldn't need any extra packages yet
            ;;
        centos) # Always install EPEL
            local epel_version="EPEL_${OS_VERSION}"
            if [ ! -z "${!epel_version}" ]; then
                rpm -ivh ${!epel_version}
            fi
            ;;
        sles)
            mkdir -v /etc/zypp/credentials.d
            cat <<EOF | tee /etc/zypp/credentials.d/NCCcredentials
username=$SLES_NCC_USERNAME
password=$SLES_NCC_PASSWORD
EOF
            cat <<EOF | tee /etc/zypp/repos.d/nu_novell_com:SLES11-SP3-Pool.repo
[nu_novell_com:SLES11-SP3-Pool]
name=SLES11-SP3-Pool
enabled=1
autorefresh=1
baseurl=https://nu.novell.com/repo/\$RCE/SLES11-SP3-Pool/sle-11-x86_64?credentials=NCCcredentials
type=rpm-md
service=nu_novell_com
EOF
            cat <<EOF | tee /etc/zypp/repos.d/nu_novell_com:SLES11-SP3-Updates.repo
[nu_novell_com:SLES11-SP3-Updates]
name=SLES11-SP3-Updates
enabled=1
autorefresh=1
baseurl=https://nu.novell.com/repo/\$RCE/SLES11-SP3-Updates/sle-11-x86_64?credentials=NCCcredentials
type=rpm-md
service=nu_novell_com
EOF
            # Add svn and git repos
            zypper -non-interactive --no-gpg-checks addrepo http://download.opensuse.org/repositories/devel:/tools:/scm/SLE_11_SP3/devel:tools:scm.repo
            zypper -non-interactive --no-gpg-checks addrepo http://download.opensuse.org/repositories/devel:tools:scm:svn/SLE_11_SP3/devel:tools:scm:svn.repo
            # Add Perl repo
            zypper -non-interactive --no-gpg-checks addrepo http://download.opensuse.org/repositories/devel:/languages:/perl/SLE_11_SP3/devel:languages:perl.repo
            ;;
        rhel)
            # For now, use CentOS repositories as the binaries are built from the same source code
            cat <<EOF | tee /etc/yum.repos.d/CentOS-Base.repo
[CentOS-${OS_VERSION}-Base]
name=CentOS el${OS_VERSION} - Base
baseurl=http://mirror.centos.org/centos/${OS_VERSION}/os/\$basearch/
gpgcheck=0
EOF
            # And EPEL
            local epel_version="EPEL_${OS_VERSION}"
            if [ ! -z "${!epel_version}" ]; then
                rpm -ivh ${!epel_version}
            fi
            ;;

    esac
}

function install_package()
{
    local Packages="$@"
    case "$OS_FLAVOUR" in
        debian|ubuntu)
            apt-get -y --force-yes --allow-unauthenticated update
            apt-get -y --force-yes --allow-unauthenticated install $Packages;;
        suse|sles)
            zypper -non-interactive --no-gpg-checks refresh
            zypper -non-interactive --no-gpg-checks install $Packages;;
        rhel|centos)
            yum -y install $Packages;;
    esac
}

function add_user()
{
    local User="$1"
    local Password="$2"
    useradd -ms/bin/bash "$User"
    echo "$User:$Password" | chpasswd
    echo "$User ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
}

function add_config()
{
    cp "$BUILD_DIR/config/logrotate.conf" /etc/logrotate.conf
    cp "$BUILD_DIR/config/ssh_config" /etc/ssh/ssh_config
    cp "$BUILD_DIR/config/sshd_config" /etc/ssh/sshd_config
}

function install_runit()
{
    case "$OS_FLAVOUR" in
        debian|ubuntu) 
            install_package runit
            ;;
        rhel|centos) 
            # Install with yum in case of deps...
            curl "$RUNIT_EL_REPO" | bash
            yum -y install runit
            rm -vf /etc/yum.repos.d/imeyer_runit.repo
            yum -y clean all
            ;;
        sles|suse)
            rpm -ivh "$RUNIT_SUSE_REPO"
            ;;
    esac
}

function install_pidone()
{
    cp "$BUILD_DIR/bin/pidone" /sbin
}

function install_dependencies()
{
    # These should be available as-is on all platforms
    local std_pkgs=(git subversion vim python expect perl wget curl tar zip sudo logrotate patch)

    # These are specific to each distribution
    local deb_pkgs=(default-jre-headless openssh-server subversion git lsb-core)
    local el_pkgs=(redhat-lsb subversion git java openssh-server)
    local suse_pkgs=(java lsb lsb-release openssh)

    case "$OS_FLAVOUR" in
        ubuntu|debian)
            install_package ${std_pkgs[*]} ${deb_pkgs[*]}
            ;;
        centos|rhel) 
            if [ "$OS_VERSION" -eq 5 ]; then
                install_package ${std_pkgs[*]} ${el_pkgs[*]} python26
            else
                install_package ${std_pkgs[*]} ${el_pkgs[*]}
            fi
            ;;
        suse|sles) 
            install_package ${std_pkgs[*]} ${suse_pkgs[*]}
            ;;
    esac
}

function upgrade_packages()
{
    case "$OS_FLAVOUR" in
        debian|ubuntu)
            apt-get -y --force-yes --allow-unauthenticated update
            apt-get -y --force-yes --allow-unauthenticated upgrade
            ;;
        suse|sles)
            zypper -non-interactive --no-gpg-checks refresh
            zypper -non-interactive --no-gpg-checks update
            ;;
        rhel|centos)
            yum -y update
            ;;
    esac
}

function generate_host_keys()
{
    if [ ! -f '/etc/ssh/ssh_host_rsa_key' ]; then
        ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa
    fi
    if [ ! -f '/etc/ssh/ssh_host_dsa_key' ]; then
        ssh-keygen -f /etc/ssh/ssh_host_dsa_key -N '' -t dsa
    fi
}

function add_runit_config()
{
    if [ ! -d '/etc/service' ]; then
        mkdir -v /etc/service
    fi
    cp -arv /build/runit/* /etc/service
}

function polish()
{
    sed -i -e '/^\s*Defaults\s*requiretty.*$/d' /etc/sudoers
    touch /var/log/syslog
}

function cleanup()
{
    rm -vrf "$BUILD_DIR"
    rm -vrf /root/* /root/.bash_history 
    rm -vrf /var/tmp/* /tmp/*
    rm -vrf /var/lib/apt/lists
}

main
