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

export PS0='\[\e]133;C\e\\\]'
export PS1='\[\e]133;D;$?\e\\\]\[\e]133;A\e\\\]'"${PS1}"'\[\e]9;9;"$(wslpath -w "${PWD}")"\e\\\]\[\e]133;B\e\\\]'
export PS2=''

unset DEFAULT_PROMPT
unset DESIRED_PROMPT
