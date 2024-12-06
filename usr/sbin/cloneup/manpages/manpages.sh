#!/bin/bash

# make man pages for clone utility

shopt -s extglob # use extended globbing

SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd) # script dir
readonly SCRIPTDIR

# get entries under script dir
mapfile -t entries < <(grep --exclude=*.sh "TH" "$SCRIPTDIR"/*)

SCRIPTNAME=$(basename $(dirname "$SCRIPTDIR"))
readonly SCRIPTNAME

readonly MPDIR="/usr/share/man/"    # man pages dir
for entry in "${entries[@]}"; do
    file="${entry%%:*}"             # get man page filename
    entry="${entry#*TH +([^0-9]) }" # get str that begins with man page page num
    n="${entry::1}"                 # get man page page num

    mkdir -p "$MPDIR"/man$n/        # make dir for man page

    # add correct extention to man page file name
    if [[ "${file##/*/}" == "$SCRIPTNAME" ]]; then
        entry="$MPDIR/man$n/${file##/*/}.$n"
    else
        entry="$MPDIR/man$n/${file##/*/}.conf.$n"
    fi

    cp "$file" "$entry" # copy man page to man dir
    gzip -f "$entry"    # compress man page
done
