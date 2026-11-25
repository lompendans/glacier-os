[[ -f ~/.bashrc ]] && . ~/.bashrc
# Start the Frost desktop on the first virtual terminal.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_VTNR:-}" = 1 ]; then
    exec start-hyprland >"$HOME/.frost-session.log" 2>&1
fi
