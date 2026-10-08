#!/usr/bin/env bash
# Run in Type B Ubuntu WSL or the prepared Ubuntu VM. No installs/downloads.
# For a VM user without Docker socket access: sudo bash Show-TypeB-LinuxVersions.sh

if [[ -f /etc/profile.d/typeb-engineering.sh ]]; then
    . /etc/profile.d/typeb-engineering.sh
fi
export UV_PYTHON_DOWNLOADS=never
failed_commands=0

show_version() {
    printf '\n>'
    printf ' %q' "$@"
    printf '\n'
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'NOT FOUND: %s\n' "$1"
        failed_commands=$((failed_commands + 1))
        return
    fi
    "$@" 2>&1
    local command_status=$?
    if (( command_status != 0 )); then
        printf 'Exit code: %s\n' "$command_status"
        failed_commands=$((failed_commands + 1))
    fi
}

show_version cat /etc/os-release
show_version uname -m
show_version python --version
show_version uv --version
show_version uv python find --python-preference only-managed 3.13
show_version conda --version
show_version git --version
show_version git lfs version
show_version ssh -V
show_version curl --version
show_version wget --version
show_version tmux -V
show_version ffmpeg -hide_banner -version
show_version ffprobe -hide_banner -version
show_version gcc --version
show_version g++ --version
show_version make --version
show_version cmake --version
show_version docker version
show_version docker compose version

if (( failed_commands > 0 )); then
    printf '\nCommands needing attention: %s\n' "$failed_commands"
    printf 'If Docker says permission denied in the Ubuntu VM, rerun with sudo.\n'
    exit 1
fi
