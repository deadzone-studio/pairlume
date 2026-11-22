# Hyprland

`pairlume-ui` opens the pairing window. It is a layer called `pairlume`.

## Colors from the wallpaper

Add the template to `~/.config/matugen/config.toml`:

```toml
[templates.pairlume]
input_path = "/path/to/pairlume/contrib/matugen/pairlume-colors.json"
output_path = "~/.config/pairlume/colors.json"
```

An open window follows at once.

## Glass

The window is nearly solid. With blur behind it, set `glass` in the template lower (0.3 to 1, for example `0.6`) and let
Hyprland blur the `pairlume` layer with a layer rule.
