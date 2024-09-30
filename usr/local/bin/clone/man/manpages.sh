#!/bin/bash

# make man pages for clone.sh

readonly MPDIR="/usr/local/man/"                         # man pages dir
SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd) # script dir
readonly SCRIPTDIR

# get entries under man dir
mapfile -t entries < <(grep --exclude=*.sh "TH" "$SCRIPTDIR"/*)

for entry in "${entries[@]}"; do
    file="${entry%%:*}"         # get man page filename
    entry="${entry#*TH man }"    # get str that begins with man page page num
    n="${entry::1}"             # get man page page num

    sudo mkdir -p "$MPDIR"/man$n/                  # make dir for man page
    sudo cp "$file" "$MPDIR"/man$n/${file##/*/}.$n # copy man page to man dir
    sudo gzip "$MPDIR"/man$n/${file##/*/}.$n       # compress man page
done
