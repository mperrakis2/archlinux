# If not running interactively, don't do anything
[[ "${-#*i}" == "$-" ]] && return

# different parts of displayed text
# ---------------------------------
# E: errors and informational messages
# N: line numbers enabled via the -N option
# P: prompts
# S: search results
# W: the highlight enabled via the -w option
# d: bold text
# s: standout test
# u: underlined text

# color codes
# -----------
# y: yellow, r: red, g: green, k: black, w: white, c: cyan
# if capital letter, the color codes above are bright

# set colors for less so that man pages are more readable
# the '-D' option sets the foreground and background color of the text part
# e.g. -DEYR: errors in yellow foreground and red background
export LESS='-WR --use-color -DEwr$DPkG$$DNc$DSkg$DWkc$Dd+Y$Ds+wk$Du+C$'
export MANPAGER="less $LESS"
export MANROFFOPT="-P -c"

BOLD=$(tput bold) # bold colors foreground
CYAN="$BOLD$(tput setaf 6)"   
RED="$BOLD$(tput setaf 1)"
GREEN="$BOLD$(tput setaf 2)"  
OFF=$(tput sgr0) # turn off all attributes

if [[ "$USER" == root ]]; then # color & prompt suffix for root
    color="$RED"
    suffix="#"
else # color & prompt suffix for all other users
    color="$CYAN"
    suffix="$"
fi

# \u: username
# \H: hostname
# \W: present working directory
# \A: 24 hour format
export PS1="[$color\u$OFF@$GREEN\H$OFF: $color\w$OFF $GREEN\A$OFF]$suffix "
unset BOLD CYAN RED GREEN OFF

export HISTCONTROL=erasedups

source /usr/share/doc/pkgfile/command-not-found.bash
