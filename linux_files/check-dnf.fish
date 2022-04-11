#!/usr/bin/fish

# Only the default WSL user should run this script
if not id -Gn | string match -rq 'adm.*wheel|wheel.*adm'
    exit
end

if test -z "$WSL2"
    sudo check-dnf
end
