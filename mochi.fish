#!/usr/bin/env fish

# options
complete -c mochi -a "(mochi -option-list)"

# files
complete -c mochi -x -a "(
__fish_complete_suffix .ml
__fish_complete_suffix .cegar
)"
