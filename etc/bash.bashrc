#
# /etc/bash.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Prevent doublesourcing
if [[ -z "${BASHRCSOURCED}" ]] ; then
  BASHRCSOURCED="Y"
  # the check is bash's default value
  [[ "$PS1" = '\s-\v\$ ' ]] && PS1='[\u@\h \W]\$ '
  case ${TERM} in
    Eterm*|alacritty*|aterm*|foot*|gnome*|konsole*|kterm*|putty*|rxvt*|tmux*|xterm*)
      PROMPT_COMMAND+=('printf "\033]0;%s@%s:%s\007" "${USER}" "${HOSTNAME%%.*}" "${PWD/#$HOME/\~}"')
      ;;
    screen*)
      PROMPT_COMMAND+=('printf "\033_%s@%s:%s\033\\" "${USER}" "${HOSTNAME%%.*}" "${PWD/#$HOME/\~}"')
      ;;
  esac
fi

if [[ -r /usr/share/bash-completion/bash_completion ]]; then
  . /usr/share/bash-completion/bash_completion
fi

# system-wide aliases (affect all users) 

alias ls="ls -F --color=auto"
alias l=ls
alias la="ls -A"
alias ll="ls -lah"

alias grep="grep --color=auto"
alias fgrep="grep -F --color=auto"
alias egrep="grep -E --color=auto"

alias diff='diff --color=auto'

alias sudo="sudo " # so that aliases can be used when calling sudo

_keyring=\
"'pacman' -Qu archlinux-keyring && "\
"sudo 'pacman' --noconfirm -Sy archlinux-keyring; "\
"(( \$(id -u) != 0 ))"

if groups $(whoami) | grep -q wheel; then
    _underscore="(( \$? )) && echo sudo > /dev/null || echo '' > /dev/null"
    alias pacman="sh -c '$_keyring'; $_underscore; \$_ 'pacman'"
    alias paru="$_keyring; 'paru'"
    export SUDO_EDITOR=mousepad
    unset _underscore
elif groups $(whoami) | grep -q root; then
    alias pacman="$_keyring; 'pacman'"
fi
unset _keyring

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
# \u: username
# \H: hostname
# \W: present working directory
# \A: 24 hour format

if [[ "$USER" == root ]]; then # color & prompt suffix for root
    declare -i color=31 # red
    suffix="#"
else # color & prompt suffix for all other users
    declare -i color=36 # light cyan
    suffix="$"
fi

PS1="[\[\e[1;${color}m\]\u\[\e[0m\]@\[\e[1;32m\]\H\[\e[0m\]: "
PS1+="\[\e[1;${color}m\]\w\[\e[0m\] \[\e[1;32m\]\A\[\e[0m\]]$suffix "
export PS1
export HISTCONTROL=erasedups
export HISTTIMEFORMAT='%F %T '

# for the following see
# https://wiki.archlinux.org/title/Hardware_video_acceleration#Configuring_Vulkan_Video
export ANV_VIDEO_DECODE=1
export RADV_PERFTEST=video_decode,video_encode

source /usr/share/doc/pkgfile/command-not-found.bash
