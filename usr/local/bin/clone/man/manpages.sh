#!/bin/bash

# make man pages for clone.sh

readonly MPDIR="/usr/local/man/"                         # man pages dir
SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd) # script dir
readonly SCRIPTDIR

mapfile -t dirs < <(find "$SCRIPTDIR"/* -type d) # get man page dirs

for dir in "${dirs[@]}"; do
    n=${dir: -1}                # get last char of dir which is a digit
    file=$(find "$dir" -type f) # get man page file under dir

    sudo mkdir -p "$MPDIR"/man$n/                  # make dir for man page
    sudo cp "$file" "$MPDIR"/man$n/${file##/*/}.$n # copy man page to man dir
    sudo gzip "$MPDIR"/man$n/${file##/*/}.$n       # compress man page
done
