-- Frost — Glacier OS compositor settings (Hyprland 0.57+, Lua config)
-- Installed to /etc/skel/.config/hypr/hyprland.lua; users can edit their copy freely.
-- Reference: https://wiki.hypr.land/configuring/

local terminal    = "foot"
local fileManager = "thunar"
local browser     = "firefox"
local qs          = "qs -p /usr/share/frost/quickshell"

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
-- Virtual machine displays (VirtualBox, VMware, QEMU) report a 0x0 mm physical size, which makes
-- "auto" pick 2x and leaves e.g. a 640x400 desktop on a 1280x800 VM window. Use 1x there.
for i = 1, 4 do
    hl.monitor({ output = "Virtual-" .. i, mode = "preferred", position = "auto", scale = 1 })
end

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QUICK_CONTROLS_STYLE", "Basic")

hl.on("hyprland.start", function()
    hl.exec_cmd("swaybg -m fill -i /usr/share/backgrounds/glacier/glacier.png")
    hl.exec_cmd("frost-qs /usr/share/frost/quickshell")
    hl.exec_cmd("mako")
    -- live ISO only: greet with the installer (the installer removes this .desktop file)
    hl.exec_cmd("test -f /usr/share/applications/glacier-installer.desktop && frost-qs /usr/share/glacier-installer")
end)

---- Look and feel: liquid glass ----
hl.config({
    general = {
        gaps_in  = 6,
        gaps_out = 14,
        border_size = 1,
        col = {
            active_border   = { colors = { "rgba(ffffffaa)", "rgba(ffffff22)" }, angle = 45 },
            inactive_border = "rgba(ffffff1f)",
        },
        resize_on_border = true,
        layout = "dwindle",
    },

    decoration = {
        rounding       = 18,
        rounding_power = 2.4,
        active_opacity   = 1.0,
        inactive_opacity = 0.97,

        shadow = {
            enabled      = true,
            range        = 30,
            render_power = 3,
            color        = "rgba(00000059)",
        },

        blur = {
            enabled    = true,
            variant    = "frost",   -- frosted-glass blur; glass.* below tunes refraction
            size       = 10,
            passes     = 3,
            noise      = 0.02,
            contrast   = 1.0,
            brightness = 1.05,
            vibrancy   = 0.25,
            popups     = true,
            glass = {
                refraction = 0.6,
                roughness  = 0.15,
                size       = 14,
            },
        },
    },

    animations = { enabled = true },
    dwindle    = { preserve_split = true },
    input = {
        kb_layout    = "us",
        kb_variant   = "",
        follow_mouse = 1,
        touchpad     = { natural_scroll = true },
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
    },
})

hl.curve("glass", { type = "bezier", points = { { 0.2, 0.9 }, { 0.3, 1.12 } } })
hl.curve("soft",  { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.curve("jelly", { type = "spring", mass = 1, stiffness = 220, damping = 20 })
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 4.5, spring = "jelly", style = "popin 88%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3,   bezier = "soft",  style = "popin 92%" })
hl.animation({ leaf = "layersIn",   enabled = true, speed = 4,   bezier = "glass", style = "popin 94%" })
hl.animation({ leaf = "layersOut",  enabled = true, speed = 2,   bezier = "soft",  style = "fade" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4,   bezier = "soft" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5,   bezier = "soft",  style = "slide" })

---- Liquid glass on the shell surfaces ----
-- blur what is behind each Frost layer; ignore its transparent margins
for _, ns in ipairs({ "frost-bar", "frost-dock", "frost-cc", "notifications" }) do
    hl.layer_rule({ name = "glass-" .. ns, match = { namespace = ns }, blur = true, ignore_alpha = 0.05 })
end
hl.layer_rule({ name = "glass-launcher", match = { namespace = "frost-launcher" }, blur = true, ignore_alpha = 0.3 })

-- the installer is a dialog: float it, centred, at its designed size
hl.window_rule({ name = "installer", match = { title = "^(Install Glacier OS)$" }, float = true, center = true, size = "880 580" })

-- glass terminal
hl.window_rule({ name = "glass-terminal", match = { class = "^(foot)$" }, opacity = "0.88 0.82" })

---- Key bindings ----
local mod = "SUPER"
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Space",  hl.dsp.exec_cmd(qs .. " ipc call frost launcher"))
hl.bind(mod .. " + P",      hl.dsp.exec_cmd(qs .. " ipc call frost packages"))
hl.bind(mod .. " + A",      hl.dsp.exec_cmd(qs .. " ipc call frost controlCenter"))
hl.bind(mod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + B",      hl.dsp.exec_cmd(browser))
hl.bind(mod .. " + Q",      hl.dsp.window.close())
hl.bind(mod .. " + F",      hl.dsp.window.fullscreen())
hl.bind(mod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())

for _, d in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mod .. " + " .. d, hl.dsp.focus({ direction = d }))
end
for i = 1, 9 do
    hl.bind(mod .. " + " .. i,           hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i,   hl.dsp.window.move({ workspace = i }))
end

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -c backlight set 5%+"),             { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -c backlight set 5%-"),             { locked = true, repeating = true })
