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
layers and writes nothing to your config. Without blur they are nearly solid, and so are the texts: there is a lot to read. `glass` in `colors.json` (0.2 to 1) sets it.

## Keys of the texts

`Ctrl+K` searches, `Alt+Down` and `Alt+Up` go through the conversations, `Alt+1` to `Alt+9` open one, `Ctrl+Shift+C` copies the
code that came today, `Shift+Enter` starts a new line, `Esc` goes back.
