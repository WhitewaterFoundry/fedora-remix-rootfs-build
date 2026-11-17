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

# Do not export the prompts: they contain bash-only syntax that breaks other
# shells (e.g. zsh) started from bash. Also avoid wrapping the prompt twice
# when this file is sourced again by a nested shell.
# shellcheck disable=SC2089
case "${PS1}" in
  *'133;A'*) ;;
  *)
    PS0='\[\e]133;C\e\\\]'
    if command -v wslpath > /dev/null 2>&1; then
      PS1='\[\e]133;D;$?\e\\\]\[\e]133;A\e\\\]'"${PS1}"'\[\e]9;9;"$(wslpath -w "${PWD}")"\e\\\]\[\e]133;B\e\\\]'
    else
      PS1='\[\e]133;D;$?\e\\\]\[\e]133;A\e\\\]'"${PS1}"'\[\e]133;B\e\\\]'
    fi
    ;;
esac
PS2='> '
# shellcheck disable=SC2090,SC3045
export -n PS0 PS1 PS2 2> /dev/null

unset DEFAULT_PROMPT
unset DESIRED_PROMPT
