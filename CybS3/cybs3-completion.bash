#!/bin/bash

# CybS3 Bash Completion Script
# Install by adding 'source /path/to/cybs3-completion.bash' to your ~/.bashrc

# Helper function to get vault names from encrypted config
_cybs3_get_vaults() {
    if [[ -f ~/.cybs3/config.enc ]]; then
        # Try to decrypt and parse vault names (requires mnemonic or keychain)
        # For now, provide silent fallback since we can't decrypt without user input
        :
    fi
}

# Helper function to get bucket names from current vault
_cybs3_get_buckets() {
    local vault=$1
    if [[ -z "$vault" ]]; then
        return 0
    fi
    # Try to query S3 buckets for the given vault
    # This would require the vault to be authenticated
    # For now, provide silent fallback
    :
}

_cybs3() {
    local cur prev words cword
    _init_completion || return

    # Available top-level commands
    local commands="login logout keys vaults config files folders buckets help"

    # Keys subcommands
    local keys_commands="create validate rotate"

    # Vaults subcommands
    local vaults_commands="add list select delete"

    # Files subcommands
    local files_commands="list get put delete copy"

    # Folders subcommands
    local folders_commands="put get sync watch"

    # Buckets subcommands
    local buckets_commands="list create"

    case $prev in
        cybs3)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            return 0
            ;;
        keys)
            COMPREPLY=( $(compgen -W "$keys_commands" -- "$cur") )
            return 0
            ;;
        vaults)
            COMPREPLY=( $(compgen -W "$vaults_commands" -- "$cur") )
            return 0
            ;;
        files)
            COMPREPLY=( $(compgen -W "$files_commands" -- "$cur") )
            return 0
            ;;
        folders)
            COMPREPLY=( $(compgen -W "$folders_commands" -- "$cur") )
            return 0
            ;;
        buckets)
            COMPREPLY=( $(compgen -W "$buckets_commands" -- "$cur") )
            return 0
            ;;
        --vault)
            # Attempt to complete with available vault names
            # Note: This requires access to the config file
            local vaults
            if command -v cybs3 &> /dev/null && [[ -f ~/.cybs3/config.enc ]]; then
                # Optional: uncomment if vault listing is available
                # vaults=$(cybs3 vaults list --json 2>/dev/null | grep -oP '"name"\s*:\s*"\K[^"]+' 2>/dev/null)
                if [[ -n "$vaults" ]]; then
                    COMPREPLY=( $(compgen -W "$vaults" -- "$cur") )
                fi
            fi
            return 0
            ;;
        --bucket)
            # Attempt to complete with available bucket names
            # This requires authenticating to S3
            local buckets
            if command -v cybs3 &> /dev/null; then
                # Optional: uncomment if authenticated bucket listing is available
                # buckets=$(cybs3 buckets list --json 2>/dev/null | grep -oP '"bucket"\s*:\s*"\K[^"]+' 2>/dev/null)
                if [[ -n "$buckets" ]]; then
                    COMPREPLY=( $(compgen -W "$buckets" -- "$cur") )
                fi
            fi
            return 0
            ;;
    esac

    # File/directory completion for relevant commands
    case ${words[1]} in
        files)
            case ${words[2]} in
                put|get)
                    _filedir
                    return 0
                    ;;
            esac
            ;;
        folders)
            case ${words[2]} in
                put|get|sync|watch)
                    _filedir
                    return 0
                    ;;
            esac
            ;;
    esac

    # Option completion
    case $cur in
        -*)
            local options="--help --verbose --vault --bucket --endpoint --access-key --secret-key --region --ssl --no-ssl --json --dry-run --force"
            COMPREPLY=( $(compgen -W "$options" -- "$cur") )
            return 0
            ;;
        s3://*)
            # S3 path completion (basic)
            return 0
            ;;
    esac
}

complete -F _cybs3 cybs3
