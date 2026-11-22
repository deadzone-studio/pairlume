# Hyprland

`pairlume-ui` opens the pairing window, `pairlume-ui messages` the texts in a window, `pairlume-ui panel` at the edge of
the screen, `pairlume-ui bubbles` as faces. All but `messages` are layers called `pairlume`.

## Colors from the wallpaper

With DarkShadowShell the windows take its palette by themselves. Anywhere else add the template to
`~/.config/matugen/config.toml`:

```toml
[templates.pairlume]
input_path = "/path/to/pairlume/contrib/matugen/pairlume-colors.json"
output_path = "~/.config/pairlume/colors.json"
```

An open window follows at once.

## Glass

When Hyprland's blur is on, the windows are thin glass: Pairlume asks Hyprland (0.55 or newer) at run time to blur its
layers and writes nothing to your config. Without blur they are nearly solid. `glass` in `colors.json` (0.2 to 1) sets it.
