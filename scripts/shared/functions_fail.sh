#!/usr/bin/env bash
set -e

function realpath()
{
  [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

# # Requires that the path exist.
# function make_absolute()
# {
#   if [ -z "$1" ]; then
#     echo "Usage: make_absolute \"<relative_path>\" <?relative_to>"
#     return 1
#   fi
#
#   echo $(basename $( cd ${2:-$(pwd)}/${1} && pwd ))
# }

# Utility functions.
function lowercase()
{
  if [ -z "$1" ]; then
    echo "Usage: lowercase \"A StrinG to MakE lowercasE\""
    return 1
  fi

  echo "$1" | sed "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/"
  return 0
}

# Takes a string and removes all duplicate tokens.
function sort_and_remove_duplicates()
{
  if [ -z "$1" ]; then
    echo "Usage: sort_and_remove_duplicates \"a list of tokens tokens\""
    return 1
  fi

  echo $(echo ${1} | tr ' ' '\n' | sort -u | tr '\n' ' ')
  return 0
}

# Returns the OS
function os()
{
  local OS=`lowercase \`uname\``

  if [ "$OS" == "darwin" ]; then
  	OS="osx"
  elif [ "$OS" == "windowsnt" ] ; then
  	OS="vs"
  elif [ "${OS:0:5}" == "mingw" -o "$OS" == "msys_nt-6.3" ]; then
  	OS="msys2"
  elif [ "$OS" == "linux" ]; then
  	ARCH=`uname -m`
  	if [ "$ARCH" == "i386" -o "$ARCH" == "i686" ] ; then
  		OS="linux"
  	elif [ "$ARCH" == "x86_64" ] ; then
  		OS="linux64"
  	elif [ "$ARCH" == "armv6l" ] ; then
  		OS="linuxarmv6l"
  	elif [ "$ARCH" == "armv7l" ] ; then
  		# Make an exception for raspberry pi to run on armv6l, to conform
  		# with openFrameworks.
  		if [ -f /opt/vc/include/bcm_host.h ]; then
  			OS="linuxarmv6l"
  		else
  			OS="linuxarmv7l"
  		fi
  	else
  		# We don't know this one, but we will try to make a reasonable guess.
  		OS="linux"$ARCH
  	fi
  fi
  echo ${OS}
  return 0
}


# Addons

# Extract ADDON_DEPENDENCIES from an addon's addon_config.mk file.
function get_dependencies_for_addon()
{
  if [ -z "$1" ]; then
    echo "Usage: get_dependencies_for_addon <path_to_addon>"
    return 1
  fi

  if [ -f ${1}/addon_config.mk ]; then
    local ADDON_DEPENDENCIES=""
    while read line; do
      if [[ $line == ADDON_DEPENDENCIES* ]] ;
      then
        line=${line#*=}
        IFS=' ' read -ra ADDR <<< "$line"
        for i in "${ADDR[@]}"; do
          ADDON_DEPENDENCIES="${ADDON_DEPENDENCIES} ${i}"
        done
      fi
    done < ${1}/addon_config.mk
    echo $(sort_and_remove_duplicates "${ADDON_DEPENDENCIES}")
  fi
  return 0
}

# Extract ADDON_DEPENDENCIES from an addon's example addons.make files.
function get_dependencies_for_addon_examples()
{
  if [ -z "$1" ]; then
    echo "Usage: get_dependencies_for_addon_examples <path_to_addon>"
    return 1
  fi

  local ADDONS_REQUIRED_BY_EXAMPLES=""

  for addons_make in ${1}/example*/addons.make; do
    while read addon; do
      ADDONS_REQUIRED_BY_EXAMPLES="${ADDONS_REQUIRED_BY_EXAMPLES} ${addon}"
    done < ${addons_make}
  done
  echo $(sort_and_remove_duplicates "${ADDONS_REQUIRED_BY_EXAMPLES}")
  return 0
}


function get_all_dependencies_for_addon()
{
  if [ -z "$1" ]; then
    echo "Usage: get_all_dependencies_for_addon <path_to_addon>"
    return 1
  fi

  local ADDONS_REQUIRED=$(get_dependencies_for_addon "$1")
  local ADDONS_REQUIRED_BY_EXAMPLES=$(get_dependencies_for_addon_examples "$1")

  echo $(sort_and_remove_duplicates "${ADDONS_REQUIRED} ${ADDONS_REQUIRED_BY_EXAMPLES}")
  return 0

}

# Clone the list of addons and check to make sure all dependencies are satisfied and cloned.
function clone_addons()
{
  if [ -z "$1" ]; then
    echo "Usage: clone_addons \"ofxAddon1 ofxAddon2\""
    return 1
  fi

  for addon in "$@"
  do
    if [ ! -d ${OF_ADDONS_DIR}/${addon} ]; then
      echo "Installing: ${OF_ADDONS_DIR}/${addon}"
      git clone --quiet --depth=${ADDON_CLONE_DEPTH} -b ${ADDON_CLONE_BRANCH} https://github.com/${ADDON_CLONE_USERNAME}/${addon}.git ${OF_ADDONS_DIR}/${addon}

      local _REQUIRED_ADDONS=$(get_dependencies_for_addon ${OF_ADDONS_DIR}/${addon})

      for required_addon in ${_REQUIRED_ADDONS}
      do
        if [ ! -d ${OF_ADDONS_DIR}/${required_addon} ]; then
          clone_addons ${required_addon}
        else
          echo "Dependency satisfied: ${required_addon}"
        fi
      done
    fi
  done
  return 0
}


# Assets
function copy_shared_data_for_examples()
{
  if [ -z "$1" ]; then
    echo "Usage: install_data_for_examples <path_to_addon>"
    return 1
  fi

  # Form the shared data path.
  addon_shared_data_path=${1}/shared/data

  for required_data in $(ls ${1}/example*/bin/data/REQUIRED_DATA.txt)
  do
    # For the example data path.
    example_data_path=$(dirname ${required_data})

    # The || [ -n "$line" ]; is to help when the last line isn't a new line char.
    while read line || [ -n "$line" ];
    do
      # Make sure the data doesn't start with a comment hash #
      # Make sure that it isn't am empty line.
      if [ "${line:0:1}" != "#"  ] && [ -n "${line// }" ]; then
        # Turn the line into an array (space delimited).
        tokens=($line)
        # Get the first token -- the source location.
        data_source=${tokens[0]}

        if [ -e ${addon_shared_data_path}/${data_source} ]; then
          rsync -Pqar ${addon_shared_data_path}/${data_source} ${example_data_path}
        else
          echo "${addon_shared_data_path}/${data_source} does not exist. Did you install the data?"
        fi
      fi
    done < $required_data
  done
  return 0
}



copy_shared_data_for_examples ../..
