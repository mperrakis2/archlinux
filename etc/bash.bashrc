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
    alias pacman='$(/usr/bin/pacman_keyring.sh pacman) $(which pacman)'
    alias pacaur="sudo /usr/bin/pacman_keyring.sh && pacaur -y"
    alias paru="sudo /usr/bin/pacman_keyring.sh && paru"
    export SUDO_EDITOR=mousepad
fi
