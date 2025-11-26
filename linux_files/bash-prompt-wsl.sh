#!/bin/sh

#
# Add Windows Terminal Shell Integration codes to the prompt.

# only for bash and Windows Terminal
if [ -z "${BASH_VERSION}" ] || [ -z "${WT_SESSION}" ]; then
  return
fi

# Extracted named constants for clarity
DEFAULT_PROMPT='\s-\v\$ '
DESIRED_PROMPT='[\u@\h \W]\$ '

# Set the desired prompt only if the current prompt matches the default
if [ "$PS1" = "$DEFAULT_PROMPT" ]; then
  PS1="$DESIRED_PROMPT"
fi

export PS1='\[\033]133;D;$?\]\[\033\\\033]133;A\033\\\]'"${PS1}"'\[\033]9;9;"$(wslpath -w "${PWD}")"\033\\\]\[\033]133;B\033\\\]'

unset DEFAULT_PROMPT
unset DESIRED_PROMPT
