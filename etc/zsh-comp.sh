#compdef jkr

# Subcommand completion function
__jkr-execute-cmd() {
    local curcontext context state line
    local env_dir

    integer ret=1
    _arguments \
        -C -S \
        '--debug[enable debug mode]' \
        {-C,--directory}':Jkr directory:_directories' \
        '(-): :->jkr_plans' \
        && return

    case $state in
        (jkr_plans)
            if [[ -n ${opt_args[(I)-C|--directory]} ]]; then
                env_dir=${opt_args[${opt_args[(I)-C|--directory]}]}
            else
                env_dir=""
            fi

            __jkr_plans $env_dir && ret=0
            ;;
    esac
    return $ret
}

__jkr-list-cmd() {
    _arguments \
        -C -S \
        '--debug[enable debug mode]' \
        {-C,--directory}':Jkr directory:_directories' \
        && return
}

__jkr_plans() {
    local old_IFS="$IFS" # save IFS
    IFS=$'\n'
    if [[ -n $1 ]]; then
        _values "Available plans" $(JKR_ZSHCOMP_HELPER=y jkr list --directory=$1)
    else
        _values "Available plans" $(JKR_ZSHCOMP_HELPER=y jkr list)
    fi
    IFS="$old_IFS" # restore IFS
}

# Main completion function
_jkr() {
    local curcontext context state line
    declare -A opt_args
    integer ret=1

    _arguments \
        -C -S \
        '(-): :->subcmds' \
        '(-)*:: :->option-or-argument' \
        && return

    case $state in
        (subcmds)
            __jkr_subcmds && ret=0
            ;;
        (option-or-argument)
            if (( $+functions[__jkr-$words[1]-cmd] )); then
                _call_function ret __jkr-$words[1]-cmd
            else
                _message 'no completion'
            fi
            ;;
    esac

    return $ret
}

__jkr_subcmds() {
    _values 'Jkr command' \
            'execute[Execute a plan]' \
            'list[List jkr plans]' \
            'analyze[Analyze a result]'
}
