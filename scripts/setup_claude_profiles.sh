#!/bin/bash

__profiles_run() {
    if [[ "$__profiles_dry_run" == yes ]]; then
        printf '[dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

__profiles_shared_dir() {
    printf '%s\n' "${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
}

__profiles_state_of() {
    CLAUDE_SHARED_DIR="$(__profiles_shared_dir)" CLAUDE_REPO_CONFIG_DIR="$PWD/configs/claude" configs/bin/claude-settings-diff state "$1"
}

__profiles_file_mode() {
    if [[ -x "configs/claude/$1" ]]; then echo 755; else echo 644; fi
}

__profiles_install_with_snapshot() {
    local file=$1
    local shared_dir
    shared_dir=$(__profiles_shared_dir)
    local mode
    mode=$(__profiles_file_mode "$file")

    __profiles_run install -D -m "$mode" "configs/claude/$file" "$shared_dir/$file"
    __profiles_run install -D -m 644 "configs/claude/$file" "$shared_dir/.deployed/$file"
}

__profiles_refresh_snapshot() {
    __profiles_run install -D -m 644 "configs/claude/$1" "$(__profiles_shared_dir)/.deployed/$1"
}

__profiles_ask_overwrite() {
    local file=$1
    local shared_dir
    shared_dir=$(__profiles_shared_dir)

    printf 'Both copies of %s changed since the last deploy.\n' "$file"
    if [[ -f "$shared_dir/.deployed/$file" ]]; then
        diff -u "$shared_dir/.deployed/$file" "$shared_dir/$file"
        diff -u "$shared_dir/.deployed/$file" "configs/claude/$file"
    else
        diff -u "$shared_dir/$file" "configs/claude/$file"
    fi

    if [[ "$__profiles_dry_run" == yes ]]; then
        printf '[dry-run] would ask whether to overwrite %s\n' "$file"
        return 1
    fi
    if [[ ! -t 0 ]]; then
        printf 'No terminal: keeping the deployed %s\n' "$file"
        return 1
    fi

    local answer
    read -r -p "Overwrite deployed $file with the repo copy? [y/N] " answer
    [[ "$answer" == [yY] ]]
}

__profiles_deploy_file() {
    local file=$1
    local state
    state=$(__profiles_state_of "$file")

    case $state in
        missing-deployed|repo-ahead)
            printf 'deploy   %s (%s)\n' "$file" "$state"
            __profiles_install_with_snapshot "$file"
            ;;
        converged)
            printf 'snapshot %s (deployed copy already equals the repo)\n' "$file"
            __profiles_refresh_snapshot "$file"
            ;;
        deployed-drift)
            printf 'drift    %s (deployed copy changed, repo unchanged; kept; see claude-settings-diff)\n' "$file"
            ;;
        unknown-baseline|conflict)
            if __profiles_ask_overwrite "$file"; then
                __profiles_install_with_snapshot "$file"
            fi
            ;;
        in-sync)
            printf 'ok       %s\n' "$file"
            ;;
    esac
}

__profiles_deploy_plain_file() {
    local source=$1 destination=$2 mode=$3
    printf 'deploy   %s\n' "$destination"
    __profiles_run install -D -m "$mode" "$source" "$(__profiles_shared_dir)/$destination"
}

__profiles_deployable_plain_files() {
    (
        cd configs/claude || exit 1
        find hooks -type f \
            -not -path '*/tests/*' -not -path '*/__pycache__/*' -not -path '*/.pytest_cache/*' -not -name 'test_*' -not -name '*.pyc' | sort
        echo statusline-command.sh
    )
}

__profiles_keep_previous_base() {
    local deployed_base
    deployed_base="$(__profiles_shared_dir)/settings.base.json"
    [[ -f "$deployed_base" ]] || return 0
    cmp -s "$deployed_base" configs/claude/settings.json && return 0
    __profiles_run install -D -m 644 "$deployed_base" "$(__profiles_shared_dir)/.deployed/settings.base.json"
}

__profiles_deploy_files() {
    local file
    __profiles_run mkdir -p "$(__profiles_shared_dir)/.deployed"

    __profiles_keep_previous_base
    __profiles_deploy_plain_file configs/claude/settings.json settings.base.json 644
    while IFS= read -r file; do
        __profiles_deploy_plain_file "configs/claude/$file" "$file" "$(__profiles_file_mode "$file")"
    done < <(__profiles_deployable_plain_files)

    __profiles_deploy_file CLAUDE.md

    if [[ "$__profiles_dry_run" != yes ]]; then
        printf '%s\n' "$PWD/configs/claude" > "$(__profiles_shared_dir)/.deployed/.repo-config-dir"
    fi
}

__profiles_install_tooling() {
    __profiles_run install -D -m 755 configs/bin/claude-profile-prepare ~/.local/bin/claude-profile-prepare
    __profiles_run install -D -m 755 configs/bin/claude-settings-diff ~/.local/bin/claude-settings-diff
    __profiles_run git config core.hooksPath .githooks
}

__profiles_print_usage() {
    printf 'Usage: source scripts/setup_claude_profiles.sh [--dry-run] PHASE...\n'
    printf 'Phases: deploy-files, install-tooling\n'
}

setup_claude_profiles() {
    local __profiles_dry_run=no
    local phases=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run) __profiles_dry_run=yes; shift ;;
            deploy-files|install-tooling) phases+=("$1"); shift ;;
            *) __profiles_print_usage >&2; return 1 ;;
        esac
    done

    if [[ ${#phases[@]} -eq 0 ]]; then
        __profiles_print_usage >&2
        return 1
    fi

    local phase
    for phase in "${phases[@]}"; do
        case $phase in
            deploy-files) __profiles_deploy_files ;;
            install-tooling) __profiles_install_tooling ;;
        esac || return 1
    done
}

setup_claude_profiles "$@"
claude_profiles_status=$?

unset -f setup_claude_profiles
unset -f $(compgen -A function __profiles_)

return "$claude_profiles_status"
