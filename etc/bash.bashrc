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

if groups "$(whoami)" | grep wheel &> /dev/null; then
    pm=$(which pacman)
    pkg=archlinux-keyring
    keyring="$pm -Qu $pkg && $pm --noconfirm -Sy $pkg"
    alias pacman="$keyring; $pm"
    alias paru="$keyring; $(which paru)"
    export SUDO_EDITOR=mousepad
fi
