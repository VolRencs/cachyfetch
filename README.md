# cachyfetch

A fast and minimal system information fetcher written in [Zig](https://ziglang.org) and built with **CachyOS** in mind.

![cachyfetch screenshot](assets/cachyfetch.png)

## Features

- CachyOS ASCII logo with compact colored output
- User/host, OS, kernel, uptime, and package count
- Shell and terminal detection
- DE/WM detection for KDE Plasma, GNOME, Hyprland, Sway, and niri
- WM theme, GTK/KDE theme, icons, font, and cursor detection
- CPU, GPU, monitor, memory, swap, disk, locale, and local IP info
- Progress bars for memory, swap, and disk usage
- 16-color palette preview

## Quick start

### Build

```bash
zig build -Doptimize=ReleaseFast
```

### Run

```bash
zig build run
```

Or run the built binary directly:

```bash
./zig-out/bin/cachyfetch
```

### Install

```bash
zig build -Doptimize=ReleaseFast
sudo install -Dm755 zig-out/bin/cachyfetch /usr/local/bin/cachyfetch
```

## Requirements

### Build

- `zig` 0.15.0 or newer

### Runtime

These tools are optional and are only used when available:

- `pacman` for package counting
- `lspci` from `pciutils` for GPU detection
- `ip` from `iproute2` for local IP detection
- `gsettings` from `glib2` for GTK/GNOME theme, icon, and font detection

## Notes

- `cachyfetch` is Linux-only and reads data from `/proc`, `/sys`, desktop config files, and optional system utilities.
- KDE Plasma theme information is read directly from files in `~/.config`.
- When a command or desktop-specific source is unavailable, the corresponding field falls back to `unknown`.

## Project structure

```text
cachyfetch/
├── src/
│   ├── main.zig   # output rendering and layout
│   └── core.zig   # system information collection
├── build.zig
└── build.zig.zon
```

## License

MIT
