-- Frost Greeter — minimal Hyprland session for the Glacier OS login screen.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
for i = 1, 4 do
    hl.monitor({ output = "Virtual-" .. i, mode = "preferred", position = "auto", scale = 1 })
end

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QUICK_CONTROLS_STYLE", "Basic")

hl.on("hyprland.start", function()
    hl.exec_cmd("swaybg -m fill -i /usr/share/backgrounds/glacier/glacier.png")
    hl.exec_cmd("frost-qs /usr/share/frost/greeter")
end)

hl.config({
    decoration = {
        rounding = 24,
        blur = {
            enabled    = true,
            variant    = "frost",
            size       = 10,
            passes     = 3,
            noise      = 0.02,
            contrast   = 1.0,
            brightness = 1.05,
            vibrancy   = 0.25,
            glass = {
                refraction = 0.6,
                roughness  = 0.15,
                size       = 14,
            },
        },
    },
    animations = { enabled = true },
    input = {
        kb_layout  = "us",
        kb_variant = "",
        touchpad   = { natural_scroll = true },
    },
    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
    },
})

hl.layer_rule({ name = "glass-greeter", match = { namespace = "frost-greeter" }, blur = true, ignore_alpha = 0.05 })
