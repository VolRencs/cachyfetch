const std = @import("std");

const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const linux = std.os.linux;

pub const Info = struct {
    user: []const u8 = "user",
    hostname: []const u8 = "localhost",
    os: []const u8 = "Linux",
    kernel: []const u8 = "unknown",
    uptime: []const u8 = "unknown",
    packages: []const u8 = "unknown",
    shell: []const u8 = "unknown",
    terminal: []const u8 = "unknown",
    de: []const u8 = "unknown",
    wm: []const u8 = "unknown",
    wm_theme: []const u8 = "unknown",
    theme: []const u8 = "unknown",
    icons: []const u8 = "unknown",
    font: []const u8 = "unknown",
    cursor: []const u8 = "unknown",
    locale: []const u8 = "unknown",
    cpu: []const u8 = "unknown",
    gpu: [][]const u8 = &.{},
    monitors: [][]const u8 = &.{},
    memory: []const u8 = "unknown",
    mem_bar: []const u8 = "",
    swap: []const u8 = "disabled",
    swap_bar: []const u8 = "",
    disk: []const u8 = "unknown",
    disk_bar: []const u8 = "",
    disk_fs: []const u8 = "",
    local_ip: []const u8 = "unknown",
    colors: []const u8 = "",
};

const A = std.mem.Allocator;
const MemoryInfo = struct { total: f64, avail: f64, swap_total: f64, swap_free: f64 };
const DesktopInfo = struct { de: []const u8, wm: []const u8 };
const LookInfo = struct { wm_theme: []const u8, theme: []const u8, icons: []const u8, font: []const u8, cursor: []const u8 };
const MonitorEntry = struct { model: []const u8, port: []const u8, kind: []const u8, mode: []const u8 };

fn readFile(a: A, path: []const u8) []const u8 {
    const file = fs.openFileAbsolute(path, .{}) catch return "";
    defer file.close();
    return file.readToEndAlloc(a, 1 << 20) catch "";
}

fn run(a: A, argv: []const []const u8) []const u8 {
    var child = std.process.Child.init(argv, a);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    child.spawn() catch return "";
    const out = child.stdout.?.readToEndAlloc(a, 1 << 20) catch "";
    _ = child.wait() catch {};
    return out;
}

fn env(a: A, key: []const u8) []const u8 {
    return std.process.getEnvVarOwned(a, key) catch "";
}

fn envOr(a: A, key: []const u8, fallback: []const u8) []const u8 {
    const value = env(a, key);
    return if (value.len > 0) value else fallback;
}

fn trim(value: []const u8) []const u8 {
    return mem.trim(u8, value, " \t\r\n");
}

fn valueOr(value: []const u8, fallback: []const u8) []const u8 {
    return if (value.len > 0) value else fallback;
}

fn list1(a: A, value: []const u8) [][]const u8 {
    const out = a.alloc([]const u8, 1) catch return &.{};
    out[0] = value;
    return out;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn iniGet(data: []const u8, section: []const u8, key: []const u8) []const u8 {
    var in_section = section.len == 0;
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = trim(raw);
        if (line.len == 0) continue;
        if (line[0] == '[') {
            in_section = mem.eql(u8, line, section);
            continue;
        }
        if (!in_section or !mem.startsWith(u8, line, key)) continue;
        const rest = line[key.len..];
        if (rest.len > 0 and rest[0] == '=') return trim(rest[1..]);
    }
    return "";
}

fn splitIniValue(value: []const u8) []const u8 {
    return trim(mem.trim(u8, value, "\""));
}

fn procName(a: A, pid: u32) []const u8 {
    return trim(readFile(a, fmt.allocPrint(a, "/proc/{d}/comm", .{pid}) catch return ""));
}

fn procCmdline(a: A, pid: u32) []const u8 {
    return trim(mem.replaceOwned(u8, a, readFile(a, fmt.allocPrint(a, "/proc/{d}/cmdline", .{pid}) catch return ""), "\x00", " ") catch "");
}

fn parentPid(a: A, pid: u32) u32 {
    var it = mem.splitScalar(u8, readFile(a, fmt.allocPrint(a, "/proc/{d}/status", .{pid}) catch return 0), '\n');
    while (it.next()) |line| {
        if (mem.startsWith(u8, line, "PPid:")) return fmt.parseInt(u32, trim(line[5..]), 10) catch 0;
    }
    return 0;
}

fn selfPid() u32 {
    return @intCast(linux.getpid());
}

fn commandExists(a: A, cmd: []const u8) bool {
    const path = env(a, "PATH");
    if (path.len == 0) return false;
    var it = mem.splitScalar(u8, path, ':');
    while (it.next()) |dir| {
        const full = fmt.allocPrint(a, "{s}/{s}", .{ dir, cmd }) catch continue;
        fs.accessAbsolute(full, .{}) catch continue;
        return true;
    }
    return false;
}

fn prettyOS(a: A) []const u8 {
    var it = mem.splitScalar(u8, readFile(a, "/etc/os-release"), '\n');
    while (it.next()) |line| {
        if (!mem.startsWith(u8, line, "PRETTY_NAME=")) continue;
        return trim(mem.trim(u8, line["PRETTY_NAME=".len..], "\""));
    }
    return "Linux";
}

fn routeIface(a: A) []const u8 {
    var it = mem.splitScalar(u8, readFile(a, "/proc/net/route"), '\n');
    _ = it.next();
    while (it.next()) |line| {
        var tok = mem.tokenizeAny(u8, line, " \t");
        const iface = tok.next() orelse continue;
        const destination = tok.next() orelse continue;
        const gateway = tok.next() orelse continue;
        const flags = tok.next() orelse continue;
        if (!mem.eql(u8, destination, "00000000")) continue;
        const flags_num = fmt.parseInt(u32, flags, 16) catch 0;
        if (flags_num & 0x2 == 0) continue;
        if (mem.eql(u8, gateway, "00000000")) continue;
        return iface;
    }
    return "";
}

fn uptime(a: A) []const u8 {
    const raw = mem.sliceTo(readFile(a, "/proc/uptime"), ' ');
    const seconds = fmt.parseFloat(f64, raw) catch return "unknown";
    const total = @as(u64, @intFromFloat(seconds));
    const days = total / 86400;
    const hours = (total / 3600) % 24;
    const minutes = (total / 60) % 60;
    if (days > 0) return fmt.allocPrint(a, "{d}d {d}h {d}m", .{ days, hours, minutes }) catch "unknown";
    if (hours > 0) return fmt.allocPrint(a, "{d}h {d}m", .{ hours, minutes }) catch "unknown";
    return fmt.allocPrint(a, "{d}m", .{minutes}) catch "unknown";
}

fn packageCount(a: A) []const u8 {
    if (!commandExists(a, "pacman")) return "unknown";
    const out = trim(run(a, &.{ "pacman", "-Qq" }));
    if (out.len == 0) return "unknown";
    return fmt.allocPrint(a, "{d} (pacman)", .{mem.count(u8, out, "\n") + 1}) catch "unknown";
}

fn shellName(a: A) []const u8 {
    const shell = env(a, "SHELL");
    if (shell.len > 0) return fs.path.basename(shell);
    return procName(a, parentPid(a, selfPid()));
}

fn terminalFromEnv(a: A) []const u8 {
    for (&[_][2][]const u8{
        .{ "KONSOLE_VERSION", "konsole" },
        .{ "KITTY_WINDOW_ID", "kitty" },
        .{ "ALACRITTY_SOCKET", "alacritty" },
        .{ "WEZTERM_UNIX_SOCKET", "wezterm" },
        .{ "GHOSTTY_BIN_DIR", "ghostty" },
        .{ "TERMUX_VERSION", "termux" },
        .{ "FOOT_SOCKET", "foot" },
    }) |pair| {
        if (env(a, pair[0]).len > 0) return pair[1];
    }
    for (&[_][]const u8{ "TERM_PROGRAM", "TERMINAL" }) |key| {
        const value = env(a, key);
        if (value.len > 0) return value;
    }
    return "";
}

fn ignoreProcess(name: []const u8) bool {
    for (&[_][]const u8{
        "bash", "zsh",  "fish", "sh",      "dash", "brush", "nu",
        "sudo", "doas", "env",  "timeout", "zig",  "build", "cachyfetch",
    }) |item| {
        if (mem.eql(u8, name, item)) return true;
    }
    return false;
}

fn terminalAlias(text: []const u8) []const u8 {
    for (&[_][2][]const u8{
        .{ "konsole", "konsole" },
        .{ "kitty", "kitty" },
        .{ "ghostty", "ghostty" },
        .{ "wezterm", "wezterm" },
        .{ "alacritty", "alacritty" },
        .{ "foot", "foot" },
        .{ "gnome-terminal", "gnome-terminal" },
        .{ "ptyxis", "ptyxis" },
        .{ "tilix", "tilix" },
        .{ "xfce4-terminal", "xfce4-terminal" },
    }) |item| {
        if (containsIgnoreCase(text, item[0])) return item[1];
    }
    return "";
}

fn terminalName(a: A) []const u8 {
    const from_env = terminalFromEnv(a);
    if (from_env.len > 0) return from_env;
    var pid = parentPid(a, selfPid());
    var depth: usize = 0;
    while (pid > 1 and depth < 16) : (depth += 1) {
        const name = procName(a, pid);
        const cmd = procCmdline(a, pid);
        const alias = terminalAlias(name);
        if (alias.len > 0) return alias;
        const cmd_alias = terminalAlias(cmd);
        if (cmd_alias.len > 0) return cmd_alias;
        if (name.len > 0 and !ignoreProcess(name)) return name;
        pid = parentPid(a, pid);
    }
    return "unknown";
}

fn detectDesktop(a: A) DesktopInfo {
    const current = env(a, "XDG_CURRENT_DESKTOP");
    const session = env(a, "XDG_SESSION_DESKTOP");
    const desktop = env(a, "DESKTOP_SESSION");
    const hint = if (current.len > 0) current else if (session.len > 0) session else desktop;

    if (containsIgnoreCase(hint, "KDE") or containsIgnoreCase(hint, "Plasma")) {
        return .{ .de = "KDE Plasma", .wm = "kwin_wayland" };
    }
    if (containsIgnoreCase(hint, "GNOME")) return .{ .de = "GNOME", .wm = "gnome-shell" };
    if (containsIgnoreCase(hint, "Hyprland")) return .{ .de = "Hyprland", .wm = "Hyprland" };
    if (containsIgnoreCase(hint, "sway")) return .{ .de = "Sway", .wm = "sway" };
    if (containsIgnoreCase(hint, "niri")) return .{ .de = "niri", .wm = "niri" };

    var pid = parentPid(a, selfPid());
    var depth: usize = 0;
    while (pid > 1 and depth < 12) : (depth += 1) {
        const name = procName(a, pid);
        if (mem.eql(u8, name, "kwin_wayland")) return .{ .de = "KDE Plasma", .wm = "kwin_wayland" };
        if (mem.eql(u8, name, "gnome-shell")) return .{ .de = "GNOME", .wm = "gnome-shell" };
        if (mem.eql(u8, name, "Hyprland")) return .{ .de = "Hyprland", .wm = "Hyprland" };
        if (mem.eql(u8, name, "sway")) return .{ .de = "Sway", .wm = "sway" };
        if (mem.eql(u8, name, "niri")) return .{ .de = "niri", .wm = "niri" };
        pid = parentPid(a, pid);
    }
    return .{ .de = if (hint.len > 0) hint else "unknown", .wm = "unknown" };
}

fn gsettings(a: A, schema: []const u8, key: []const u8) []const u8 {
    if (!commandExists(a, "gsettings")) return "";
    return trim(mem.trim(u8, run(a, &.{ "gsettings", "get", schema, key }), "'\""));
}

fn kdeConfig(a: A, home: []const u8, file: []const u8, section: []const u8, key: []const u8) []const u8 {
    return iniGet(readFile(a, fmt.allocPrint(a, "{s}/.config/{s}", .{ home, file }) catch return ""), section, key);
}

fn prettyLookAndFeel(a: A, package: []const u8) []const u8 {
    if (package.len == 0) return "";
    var name = package;
    if (mem.startsWith(u8, name, "org.kde.")) name = name["org.kde.".len..];
    if (mem.endsWith(u8, name, ".desktop")) name = name[0 .. name.len - ".desktop".len];
    if (containsIgnoreCase(name, "breezedark")) return "Breeze Dark";
    if (containsIgnoreCase(name, "breezetwilight")) return "Breeze Twilight";
    if (containsIgnoreCase(name, "breezelight")) return "Breeze Light";
    const raw = mem.replaceOwned(u8, a, name, "_", " ") catch name;
    return mem.replaceOwned(u8, a, raw, "-", " ") catch raw;
}

fn desktopLook(a: A, de: []const u8) LookInfo {
    const home = env(a, "HOME");
    if (mem.eql(u8, de, "KDE Plasma")) {
        const font_raw = kdeConfig(a, home, "kdeglobals", "[General]", "font");
        const qt_font = iniGet(readFile(a, fmt.allocPrint(a, "{s}/.config/Trolltech.conf", .{home}) catch ""), "[qt]", "font");
        const font_name = if (font_raw.len > 0) splitIniValue(mem.sliceTo(font_raw, ',')) else "";
        const font_size = blk: {
            if (font_raw.len == 0) break :blk "";
            const first = mem.indexOfScalar(u8, font_raw, ',') orelse break :blk "";
            const rest = font_raw[first + 1 ..];
            break :blk trim(mem.sliceTo(rest, ','));
        };
        const qt_font_name = if (qt_font.len > 0) splitIniValue(mem.sliceTo(qt_font, ',')) else "";
        const qt_font_size = blk: {
            if (qt_font.len == 0) break :blk "";
            const first = mem.indexOfScalar(u8, qt_font, ',') orelse break :blk "";
            const rest = qt_font[first + 1 ..];
            break :blk trim(mem.sliceTo(rest, ','));
        };
        const kde_theme = kdeConfig(a, home, "kdeglobals", "[General]", "ColorScheme");
        const look_and_feel = kdeConfig(a, home, "kdeglobals", "[KDE]", "LookAndFeelPackage");
        return .{
            .wm_theme = valueOr(kdeConfig(a, home, "kwinrc", "[org.kde.kdecoration2]", "theme"), valueOr(kdeConfig(a, home, "kdeglobals", "[KDE]", "widgetStyle"), "unknown")),
            .theme = valueOr(kde_theme, valueOr(prettyLookAndFeel(a, look_and_feel), "unknown")),
            .icons = valueOr(kdeConfig(a, home, "kdeglobals", "[Icons]", "Theme"), "unknown"),
            .font = if (font_size.len > 0)
                fmt.allocPrint(a, "{s} ({s}pt)", .{ font_name, font_size }) catch font_name
            else if (qt_font_size.len > 0)
                fmt.allocPrint(a, "{s} ({s}pt)", .{ qt_font_name, qt_font_size }) catch qt_font_name
            else
                valueOr(valueOr(font_name, qt_font_name), "unknown"),
            .cursor = valueOr(kdeConfig(a, home, "kcminputrc", "[Mouse]", "cursorTheme"), "unknown"),
        };
    }

    return .{
        .wm_theme = blk: {
            const value = gsettings(a, "org.gnome.desktop.interface", "gtk-theme");
            break :blk if (value.len > 0) value else "unknown";
        },
        .theme = blk: {
            const value = gsettings(a, "org.gnome.desktop.interface", "gtk-theme");
            break :blk if (value.len > 0) value else "unknown";
        },
        .icons = blk: {
            const value = gsettings(a, "org.gnome.desktop.interface", "icon-theme");
            break :blk if (value.len > 0) value else "unknown";
        },
        .font = blk: {
            const value = gsettings(a, "org.gnome.desktop.interface", "font-name");
            break :blk if (value.len > 0) value else "unknown";
        },
        .cursor = blk: {
            const value = gsettings(a, "org.gnome.desktop.interface", "cursor-theme");
            break :blk if (value.len > 0) value else "unknown";
        },
    };
}

fn localeName(a: A) []const u8 {
    for (&[_][]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" }) |key| {
        const value = env(a, key);
        if (value.len > 0) return value;
    }
    var it = mem.splitScalar(u8, readFile(a, "/etc/locale.conf"), '\n');
    while (it.next()) |line| {
        if (mem.startsWith(u8, line, "LANG=")) return trim(line[5..]);
    }
    return "unknown";
}

fn cpuName(a: A) []const u8 {
    var model: []const u8 = "";
    var cores: usize = 0;
    var it = mem.splitScalar(u8, readFile(a, "/proc/cpuinfo"), '\n');
    while (it.next()) |line| {
        if (model.len == 0 and mem.startsWith(u8, line, "model name")) {
            const colon = mem.indexOfScalar(u8, line, ':') orelse continue;
            model = trim(line[colon + 1 ..]);
        }
        if (mem.startsWith(u8, line, "processor")) cores += 1;
    }
    if (model.len == 0) return "unknown";
    return fmt.allocPrint(a, "{s} ({d})", .{ model, cores }) catch model;
}

fn gpuList(a: A) [][]const u8 {
    const out = trim(run(a, &.{"lspci"}));
    if (out.len == 0) return list1(a, "unknown");
    var list: std.ArrayList([]const u8) = .empty;
    var it = mem.splitScalar(u8, out, '\n');
    while (it.next()) |line| {
        if (mem.indexOf(u8, line, "VGA compatible controller:") == null and
            mem.indexOf(u8, line, "3D controller:") == null and
            mem.indexOf(u8, line, "Display controller:") == null) continue;
        const colon = mem.indexOf(u8, line, ": ") orelse continue;
        list.append(a, trim(line[colon + 2 ..])) catch {};
    }
    return if (list.items.len > 0) list.toOwnedSlice(a) catch list1(a, "unknown") else list1(a, "unknown");
}

fn memInfo(a: A) MemoryInfo {
    var out = std.mem.zeroes(MemoryInfo);
    var it = mem.splitScalar(u8, readFile(a, "/proc/meminfo"), '\n');
    while (it.next()) |line| {
        var tok = mem.tokenizeAny(u8, line, " \t");
        const key = tok.next() orelse continue;
        const value = tok.next() orelse continue;
        const num = fmt.parseFloat(f64, value) catch 0;
        if (mem.eql(u8, key, "MemTotal:")) out.total = num;
        if (mem.eql(u8, key, "MemAvailable:")) out.avail = num;
        if (mem.eql(u8, key, "SwapTotal:")) out.swap_total = num;
        if (mem.eql(u8, key, "SwapFree:")) out.swap_free = num;
    }
    return out;
}

fn bar(a: A, used: f64, total: f64) []const u8 {
    if (total <= 0) return "";
    const pct = used / total;
    const full = @min(@as(usize, @intFromFloat(@round(pct * 20))), 20);
    var out: std.ArrayList(u8) = .empty;
    const w = out.writer(a);
    w.writeByte('[') catch {};
    for (0..full) |_| w.writeAll("█") catch {};
    for (full..20) |_| w.writeAll("░") catch {};
    fmt.format(w, "] {d:.0}%", .{pct * 100}) catch {};
    return out.toOwnedSlice(a) catch "";
}

fn disk(a: A) struct { value: []const u8, bar_value: []const u8, fs_type: []const u8 } {
    const out = trim(run(a, &.{ "df", "-BM", "--output=size,used,fstype", "/" }));
    var it = mem.splitScalar(u8, out, '\n');
    _ = it.next();
    const line = trim(it.next() orelse return .{ .value = "unknown", .bar_value = "", .fs_type = "" });
    var toks = mem.tokenizeAny(u8, line, " \t");
    const total_raw = toks.next() orelse return .{ .value = "unknown", .bar_value = "", .fs_type = "" };
    const used_raw = toks.next() orelse return .{ .value = "unknown", .bar_value = "", .fs_type = "" };
    const fs_type = toks.next() orelse "";
    const total = fmt.parseFloat(f64, mem.trimRight(u8, total_raw, "M")) catch 0;
    const used = fmt.parseFloat(f64, mem.trimRight(u8, used_raw, "M")) catch 0;
    return .{
        .value = fmt.allocPrint(a, "{d:.1} GiB / {d:.1} GiB", .{ used / 1024.0, total / 1024.0 }) catch "unknown",
        .bar_value = bar(a, used, total),
        .fs_type = fs_type,
    };
}

fn parseIpRouteGet(a: A, out: []const u8) []const u8 {
    var tok = mem.tokenizeAny(u8, out, " \t\r\n");
    var ip: []const u8 = "";
    var dev: []const u8 = "";
    while (tok.next()) |part| {
        if (mem.eql(u8, part, "src")) ip = tok.next() orelse "";
        if (mem.eql(u8, part, "dev")) dev = tok.next() orelse "";
    }
    if (ip.len == 0) return "";
    return if (dev.len > 0) fmt.allocPrint(a, "{s} ({s})", .{ ip, dev }) catch ip else ip;
}

fn fibTrieIp(a: A) []const u8 {
    const data = readFile(a, "/proc/net/fib_trie");
    var last_ip: []const u8 = "";
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        const trimmed = trim(line);
        if (mem.startsWith(u8, trimmed, "|-- ")) {
            last_ip = trimmed[4..];
            continue;
        }
        if (!mem.eql(u8, trimmed, "/32 host LOCAL")) continue;
        if (last_ip.len == 0 or mem.startsWith(u8, last_ip, "127.")) continue;
        const iface = routeIface(a);
        return if (iface.len > 0)
            fmt.allocPrint(a, "{s} ({s})", .{ last_ip, iface }) catch last_ip
        else
            last_ip;
    }
    return "";
}

fn localIP(a: A) []const u8 {
    if (commandExists(a, "ip")) {
        const value = parseIpRouteGet(a, run(a, &.{ "ip", "-o", "-4", "route", "get", "1.1.1.1" }));
        if (value.len > 0) return value;
    }
    const fib = fibTrieIp(a);
    if (fib.len > 0) return fib;
    return "unknown";
}

fn connectorType(label: []const u8) []const u8 {
    if (mem.startsWith(u8, label, "HDMI")) return "HDMI";
    if (mem.startsWith(u8, label, "DP")) return "DP";
    if (mem.startsWith(u8, label, "eDP")) return "eDP";
    if (mem.startsWith(u8, label, "DVI")) return "DVI";
    if (mem.startsWith(u8, label, "VGA")) return "VGA";
    if (mem.startsWith(u8, label, "LVDS")) return "LVDS";
    if (mem.startsWith(u8, label, "USB-C")) return "USB-C";
    return label;
}

fn monitorModel(a: A, base: []const u8, fallback: []const u8) []const u8 {
    const edid_path = fmt.allocPrint(a, "{s}/edid", .{base}) catch return fallback;
    const edid = readFile(a, edid_path);
    if (edid.len < 128) return fallback;
    const start = 54;
    const end = @min(edid.len, start + 72);
    var i: usize = start;
    while (i + 18 <= end) : (i += 18) {
        if (edid[i] != 0 or edid[i + 1] != 0 or edid[i + 2] != 0) continue;
        if (edid[i + 3] != 0xfc) continue;
        const raw = trim(mem.trimRight(u8, edid[i + 5 .. i + 18], " \n\r"));
        if (raw.len > 0) return raw;
    }
    return fallback;
}

fn collectMonitorEntries(a: A) []MonitorEntry {
    const dir = fs.openDirAbsolute("/sys/class/drm", .{ .iterate = true }) catch return &.{};
    var it = dir.iterate();
    var list: std.ArrayList(MonitorEntry) = .empty;
    while (it.next() catch null) |entry| {
        if (!mem.startsWith(u8, entry.name, "card")) continue;
        const dash = mem.indexOfScalar(u8, entry.name, '-') orelse continue;
        const port = entry.name[dash + 1 ..];
        const base = fmt.allocPrint(a, "/sys/class/drm/{s}", .{entry.name}) catch continue;
        if (!mem.eql(u8, trim(readFile(a, fmt.allocPrint(a, "{s}/status", .{base}) catch continue)), "connected")) continue;
        const mode = blk: {
            const current = trim(readFile(a, fmt.allocPrint(a, "{s}/mode", .{base}) catch ""));
            if (current.len > 0) break :blk current;
            break :blk trim(mem.sliceTo(readFile(a, fmt.allocPrint(a, "{s}/modes", .{base}) catch ""), '\n'));
        };
        list.append(a, .{
            .model = monitorModel(a, base, port),
            .port = port,
            .kind = connectorType(port),
            .mode = mode,
        }) catch {};
    }
    return list.toOwnedSlice(a) catch &.{};
}

fn duplicateMonitorCount(entries: []const MonitorEntry, model: []const u8) usize {
    var count: usize = 0;
    for (entries) |entry| {
        if (mem.eql(u8, entry.model, model)) count += 1;
    }
    return count;
}

fn formatMonitor(a: A, entries: []const MonitorEntry, entry: MonitorEntry) []const u8 {
    const show_port = duplicateMonitorCount(entries, entry.model) > 1 or mem.eql(u8, entry.model, entry.port);
    if (entry.mode.len > 0 and show_port) {
        return fmt.allocPrint(a, "{s} ({s}) [{s}] {s}", .{ entry.model, entry.port, entry.kind, entry.mode }) catch entry.model;
    }
    if (entry.mode.len > 0) {
        return fmt.allocPrint(a, "{s} [{s}] {s}", .{ entry.model, entry.kind, entry.mode }) catch entry.model;
    }
    if (show_port) {
        return fmt.allocPrint(a, "{s} ({s}) [{s}]", .{ entry.model, entry.port, entry.kind }) catch entry.model;
    }
    return fmt.allocPrint(a, "{s} [{s}]", .{ entry.model, entry.kind }) catch entry.model;
}

fn monitors(a: A) [][]const u8 {
    const entries = collectMonitorEntries(a);
    if (entries.len == 0) return list1(a, "unknown");
    var out: std.ArrayList([]const u8) = .empty;
    for (entries) |entry| out.append(a, formatMonitor(a, entries, entry)) catch {};
    return out.toOwnedSlice(a) catch list1(a, "unknown");
}

fn colors(a: A) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    const w = out.writer(a);
    for (0..8) |i| fmt.format(w, "\x1b[{d}m  ", .{40 + i}) catch {};
    w.writeAll("\x1b[0m  ") catch {};
    for (0..8) |i| fmt.format(w, "\x1b[{d}m  ", .{100 + i}) catch {};
    w.writeAll("\x1b[0m") catch {};
    return out.toOwnedSlice(a) catch "";
}

pub fn collect(a: A) Info {
    var info = Info{};
    info.user = envOr(a, "USER", "user");
    info.hostname = valueOr(trim(readFile(a, "/proc/sys/kernel/hostname")), "localhost");
    info.os = prettyOS(a);
    info.kernel = blk: {
        var it = mem.splitScalar(u8, valueOr(trim(readFile(a, "/proc/version")), "unknown"), ' ');
        _ = it.next();
        _ = it.next();
        break :blk it.next() orelse "unknown";
    };
    info.uptime = uptime(a);
    info.packages = packageCount(a);
    info.shell = shellName(a);
    info.terminal = terminalName(a);

    const desktop = detectDesktop(a);
    info.de = desktop.de;
    info.wm = desktop.wm;
    if (mem.eql(u8, info.terminal, "unknown") and mem.eql(u8, info.de, "KDE Plasma")) {
        const home = env(a, "HOME");
        if (readFile(a, fmt.allocPrint(a, "{s}/.config/konsolerc", .{home}) catch "").len > 0) {
            info.terminal = "konsole";
        }
    }

    const look = desktopLook(a, info.de);
    info.wm_theme = look.wm_theme;
    info.theme = look.theme;
    info.icons = look.icons;
    info.font = look.font;
    info.cursor = look.cursor;
    info.locale = localeName(a);
    info.cpu = cpuName(a);
    info.gpu = gpuList(a);
    info.monitors = monitors(a);

    const m = memInfo(a);
    const mem_total = m.total / 1024.0;
    const mem_used = mem_total - (m.avail / 1024.0);
    info.memory = fmt.allocPrint(a, "{d:.0} MiB / {d:.0} MiB", .{ mem_used, mem_total }) catch "unknown";
    info.mem_bar = bar(a, mem_used, mem_total);
    if (m.swap_total > 0) {
        const swap_total = m.swap_total / 1024.0;
        const swap_used = swap_total - (m.swap_free / 1024.0);
        info.swap = fmt.allocPrint(a, "{d:.0} MiB / {d:.0} MiB", .{ swap_used, swap_total }) catch "unknown";
        info.swap_bar = bar(a, swap_used, swap_total);
    }

    const root_disk = disk(a);
    info.disk = root_disk.value;
    info.disk_bar = root_disk.bar_value;
    info.disk_fs = root_disk.fs_type;
    info.local_ip = localIP(a);
    info.colors = colors(a);
    return info;
}
