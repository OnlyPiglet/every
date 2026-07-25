# bash completion for every
_every_tasks() {
  every list --json 2>/dev/null | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//'
}

_every() {
  local cur cmds task_cmds sub
  cur="${COMP_WORDS[COMP_CWORD]}"
  cmds="list log run pause resume rm doctor version help"
  task_cmds=" log run pause resume rm "

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
    return
  fi

  sub="${COMP_WORDS[1]}"
  if [ "$COMP_CWORD" -eq 2 ] && [[ "$task_cmds" == *" $sub "* ]]; then
    COMPREPLY=( $(compgen -W "$(_every_tasks)" -- "$cur") )
  fi
}
complete -F _every every
