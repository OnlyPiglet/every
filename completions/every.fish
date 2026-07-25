# fish completion for every
function __every_tasks
    every list --json 2>/dev/null \
        | string match -r '"name":"[^"]*"' \
        | string replace -r '"name":"([^"]*)"' '$1'
end

# subcommands, only as the first argument
complete -c every -f -n __fish_use_subcommand -a list   -d 'status of everything'
complete -c every -f -n __fish_use_subcommand -a log    -d 'output of recent runs'
complete -c every -f -n __fish_use_subcommand -a run    -d 'run a task now'
complete -c every -f -n __fish_use_subcommand -a pause  -d 'stop scheduling'
complete -c every -f -n __fish_use_subcommand -a resume -d 'start scheduling again'
complete -c every -f -n __fish_use_subcommand -a rm     -d 'remove a task'
complete -c every -f -n __fish_use_subcommand -a doctor -d "why isn't it running?"
complete -c every -f -n __fish_use_subcommand -a version
complete -c every -f -n __fish_use_subcommand -a help

# task names for the task subcommands
complete -c every -f -n '__fish_seen_subcommand_from log run pause resume rm' -a '(__every_tasks)'
