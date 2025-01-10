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

# colors for bash prompt
#
# Black       0;30     Dark Gray     1;30
# Blue        0;34     Light Blue    1;34
# Green       0;32     Light Green   1;32
# Cyan        0;36     Light Cyan    1;36
# Red         0;31     Light Red     1;31
# Purple      0;35     Light Purple  1;35
# Brown       0;33     Yellow        1;33
# Light Gray  0;37     White         1;37
#
# \[\e[1;34m\] <attrib> \[\e[0m\] <- light blue <attrib>
#
# where <attrib> is
#
# \\u: username
# \\H: hostname
# \\W: present working directory
# \\A: 24 hour format

if [[ "$USER" == root ]]; then # color & prompt suffix for root
    declare -i color=31 # red
    suffix="#"
else # color & prompt suffix for all other users
    declare -i color=36 # light cyan
    suffix="$"
fi

export PS1="[\[\e[1;${color}m\]\\u\[\e[0m\]@\[\e[1;32m\]\\H\[\e[0m\]: \[\e[1;${color}m\]\\w\[\e[0m\] \[\e[1;32m\]\\A\[\e[0m\]]$suffix "
export HISTCONTROL=erasedups

source /usr/share/doc/pkgfile/command-not-found.bash
