#!/bin/sh
trap "throw_error Trapped Signal" TERM KILL INT QUIT ABRT
# State
# 0 = Not Bootstrapped
# 1 = Bootstrapped
# 2 = Preinstalled
# 3 = Installed
# 4 = PostInstalled
PHASE="0"
RECOVERY=false
# Automatically determined Variables
# from ``get_platform()``
PREFIXPLATFORM=""
SUPPORTED_PLATFORM=""

function get_platform(){
   # TODO: Distro ident
    PREFIXPLATFORM=$(uname -s)
    if [[ -z $PREFIXPLATFORM ]]; then
        throw_error "uname -s failed, windows suppport is unlikely."
    elif [[ $(tr [:upper:] [:lower:] <<< $PREFIXPLATFORM) == "linux" ]]; then
        # Attempt to grok the distro
        # This will, theoretically, pickup redhat, arch and deb derivs
        local distro_file
        distro_file=$(/etc/*-release)
        if [[ ! -z $distro_file ]]; then
            if [[ ${distro_file%%-*} != 'lsb' ]]; then
                PREFIXPLATFORM=${distro_file%%-*}

            else
                PREFIXPLATFORM=$(grep DISTRIB_ID /etc/$distro_file | sed \
                -e 's/DISTRIB_ID=\(.*\)/\1/')
            fi # != 'lsb'
        fi # -z $distro_file
    fi # -z $PREFIXPLATFORM
}

#################
# FLOW CONTROL
#################

# Get platform files applicable to our platform, and allow the user to select
# if there is more than one method
function select_platform(){
    # Get all the platform files that match our platform multiples are
    # allowed so we need a way to allow the user to select one.
    # ex: mac_brew_platform.in
    #     mac_gentoo_prefix_platform.in
    # TODO: Install file Descriptions
    # TODO: Version compatibility tests.
    # TODO: Failed install recovery
    
    # get all the platform files named $PREFIXPLATFORM_*_platform.in
    # example: darwin_gentoo_prefix_platform.in
    #          darwin_brew_platform.in
    SUPPORTED_PLATFORM=$(dirname $0)/platforms/$(tr [:upper:] [:lower:] <<< $PREFIXPLATFORM)*_platform.in
    # If there's more than one platform ask the user which we should use.
    # TODO: this should be moved to its own funtion and treated more like
    # eselect or gcc-config.
    # ex. platform# list
    #     platform# descibe 1
    #     platform# set 1
    # or something.
    if [[ $(echo $SUPPORTED_PLATFORM | wc -w) -gt 1 ]]; then
        echo "More than one possible supported method for your platform"
        local opt
        select opt in $SUPPORTED_PLATFORM; do
            if [[ -z $opt ]]; then
                echo "Please select a valid option."
            else
                SUPPORTED_PLATFORM=$opt
                break
            fi
        done
    fi
    # At this poing SUPPORTED_PLATFORM should hold the
    # platform to be installed. 
    source $SUPPORTED_PLATFORM
    if [[ -e $HOME/.$(basename $SUPPORTED_PLATFORMS .in) ]]; then
        local reply
        while true; do
            read -p "(Possibly Failed) installation in progress detected. Would you like to attempt to recover?" reply
            reply=$(tr [:upper:] [:lower:] <<< $reply)
            if [[ "$reply" == "yes" ]]; then
                ##### TODO FINISH THIS ######
                throw_error "Installation recovery is not yet supported"
                break
            elif [[ "$reply" == "no"  ]]; then
                echo "Not recovering - please examine the file $HOME/.$(basename $SUPPORTED_PLATFORMS .in) before re-running setup"
                exit 0
            else
                echo "$reply is not a valid entry"
            fi
        done
    fi
    return 0
}

# Call select_platform and source our install method
# call install_libbash as sourced from platform include
# run the platforms bootstrap method
function bootstrap(){
    select_platform && install_libbash && platform_bootstrap
}

# Call platforms postbootstrap function
# and set our stage variable to reflect
# the installer state.
function postbootstrap(){
    platform_postbootstrap
    STAGE=1
}

# Not sure the difference between postbootstrap
# and preinstall, but we'll leave it here for
# some low cost future proofing
function preinstall(){
    platform_preinstall
    STAGE=2
}

# Call the platforms install function
# NOTE: named do_install to prevent environment
# corruption. 
function do_install(){
    platform_install
    STAGE=3
}

function postinstall(){
    platform_postinstall
    STAGE=4
}

function finalize(){
    # TODO: delete the install file
    # unset all global variables
    platform_finalize
}

##################
# UTILITIES
#################

function throw_error(){
    local msg
    local default
    default="Unknown Error."
    msg=${1:-$default}
    echo "ERROR: $msg"
    exit 1
}

function fetch_to_tmp() {
    if [[ ! -e /tmp/${1##*/} ]] ; then
        if [[ -z ${FETCH_COMMAND} ]] ; then
            if [[ a$(type -t wget) == "afile" ]] ; then
                FETCH_COMMAND="wget"
            elif [[ a$(type -t ftp) == "afile" ]] ; then
                FETCH_COMMAND="ftp"
            elif [[ a$(type -t curl) == "afile" ]] ; then
                echo "WARNING: curl doesn't fail when downloading fails, please check its output carefully!"
                FETCH_COMMAND="curl -L -O"
            elif [[ a$(type -t fetch) == "afile" ]] ; then
                FETCH_COMMAND="fetch"
            else
                throw_error "no suitable download manager found (need wget, curl, fetch or ftp)"
                throw_error "could not download ${1##*/}"
                exit 1
            fi
        fi

        echo "Fetching ${1##*/}"
        pushd /tmp > /dev/null
        ${FETCH_COMMAND} "$1"
        if [[ ! -f ${1##*/} ]] ; then
            throw_error "downloading ${1} failed!"
            exit 1    
        fi
        popd > /dev/null
    fi
    return 0
}

bootstrap && postbootstrap && preinstall && do_install && postinstall
