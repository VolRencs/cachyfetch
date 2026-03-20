const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = std.mem;
const fmt = std.fmt;
const fs = std.fs;

pub const Info = struct {
    user:      []const u8 = "user",
    hostname:  []const u8 = "localhost",
    os:        []const u8 = "CachyOS",
    kernel:    []const u8 = "unknown",
    uptime:    []const u8 = "unknown",
    packages:  []const u8 = "unknown",
    shell:     []const u8 = "unknown",
    terminal:  []const u8 = "unknown",
    de:        []const u8 = "",
    wm:        []const u8 = "",
    wm_theme:  []const u8 = "unknown",
    theme:     []const u8 = "unknown",
    icons:     []const u8 = "unknown",
    font:      []const u8 = "unknown",
    cursor:    []const u8 = "unknown",
    locale:    []const u8 = "unknown",
    cpu:       []const u8 = "unknown",
    gpu:       [][]const u8 = &.{},
    monitors:  [][]const u8 = &.{},
    memory:    []const u8 = "unknown",
    mem_bar:   []const u8 = "",
    swap:      []const u8 = "disabled",
    swap_bar:  []const u8 = "",
    disk:      []const u8 = "unknown",
    disk_bar:  []const u8 = "",
    disk_fs:   []const u8 = "",
    local_ip:  []const u8 = "unknown",
    colors:    []const u8 = "",
};

fn readFile(a: Allocator, path: []const u8) []const u8 {
    const f = fs.openFileAbsolute(path, .{}) catch return "";
    defer f.close();
    return f.readToEndAlloc(a, 4 << 20) catch "";
}

fn procFile(a: Allocator, comptime fmt_str: []const u8, pid: u32) []const u8 {
    const path = fmt.allocPrint(a, fmt_str, .{pid}) catch return "";
    return readFile(a, path);
}

fn run(a: Allocator, argv: []const []const u8) []const u8 {
    const r = std.process.Child.run(.{
        .allocator        = a,
        .argv             = argv,
        .max_output_bytes = 1 << 20,
    }) catch return "";
    return r.stdout;
}

fn env(a: Allocator, key: []const u8) []const u8 {
    return std.process.getEnvVarOwned(a, key) catch "";
}

fn envOr(a: Allocator, key: []const u8, fallback: []const u8) []const u8 {
    const v = env(a, key);
    return if (v.len > 0) v else fallback;
}

fn trim(s: []const u8) []const u8 {
    return mem.trim(u8, s, " \t\r\n");
}

fn iniLine(data: []const u8, prefix: []const u8) []const u8 {
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        if (mem.startsWith(u8, line, prefix))
            return mem.trim(u8, line[prefix.len..], "\"");
    }
    return "";
}

fn iniGet(data: []const u8, section: []const u8, key: []const u8) []const u8 {
    var in_sec = section.len == 0;
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = trim(raw);
        if (line.len == 0) continue;
        if (line[0] == '[') {
            in_sec = std.ascii.eqlIgnoreCase(line, section);
            continue;
        }
        if (in_sec and mem.startsWith(u8, line, key)) {
            const rest = line[key.len..];
            if (rest.len > 0 and rest[0] == '=') return rest[1..];
        }
    }
    return "";
}

fn gtkGet(data: []const u8, key: []const u8) []const u8 {
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = mem.trim(u8, raw, " \t\r");
        if (!mem.startsWith(u8, line, key)) continue;
        const rest = mem.trimLeft(u8, line[key.len..], " \t");
        if (rest.len == 0 or rest[0] != '=') continue;
        return mem.trim(u8, rest[1..], " \t\"");
    }
    return "";
}

fn gsGet(a: Allocator, schema: []const u8, key: []const u8) []const u8 {
    const out = run(a, &.{ "gsettings", "get", schema, key });
    return mem.trim(u8, out, " \t\r\n'\"");
}

fn kdeGet(a: Allocator, file: []const u8, section: []const u8, key: []const u8) []const u8 {
    const home_val = env(a, "HOME");
    const path = fmt.allocPrint(a, "{s}/.config/{s}", .{ home_val, file }) catch return "";
    return iniGet(readFile(a, path), section, key);
}

fn gtkFile(a: Allocator, path: []const u8, key: []const u8) []const u8 {
    return gtkGet(readFile(a, path), key);
}

fn isKDE(de: []const u8) bool {
    const low = std.ascii.allocLowerString(std.heap.page_allocator, de) catch return false;
    defer std.heap.page_allocator.free(low);
    return mem.indexOf(u8, low, "kde") != null or mem.indexOf(u8, low, "plasma") != null;
}

fn isGNOME(de: []const u8) bool {
    const low = std.ascii.allocLowerString(std.heap.page_allocator, de) catch return false;
    defer std.heap.page_allocator.free(low);
    return mem.indexOf(u8, low, "gnome") != null;
}

fn progBar(a: Allocator, used: f64, total: f64) []const u8 {
    if (total == 0) return "";
    const pct = used / total;
    const n   = @min(@as(usize, @intFromFloat(@round(pct * 20))), 20);
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(a);
    w.writeByte('[') catch {};
    for (0..n)    |_| w.writeAll("█") catch {};
    for (n..20)   |_| w.writeAll("░") catch {};
    fmt.format(w, "] {d:.0}%", .{pct * 100.0}) catch {};
    return buf.toOwnedSlice(a) catch "";
}

fn uptimeStr(a: Allocator) []const u8 {
    const data  = readFile(a, "/proc/uptime");
    const field = mem.sliceTo(data, ' ');
    const secs  = fmt.parseFloat(f64, field) catch return "unknown";
    const total = @as(u64, @intFromFloat(secs));
    const mins  = (total / 60) % 60;
    const hrs   = (total / 3600) % 24;
    const days  = total / 86400;
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(a);
    if (days > 0) fmt.format(w, "{d}d ", .{days}) catch {};
    if (hrs  > 0) fmt.format(w, "{d}h ", .{hrs})  catch {};
    fmt.format(w, "{d}m", .{mins}) catch {};
    return buf.toOwnedSlice(a) catch "unknown";
}

fn parsePPid(data: []const u8) u32 {
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        if (mem.startsWith(u8, line, "PPid:")) {
            return fmt.parseInt(u32, trim(line[5..]), 10) catch 0;
        }
    }
    return 0;
}

fn isShellName(n: []const u8) bool {
    const shells = [_][]const u8{ "bash","zsh","fish","sh","dash","ksh","tcsh","csh" };
    for (shells) |s| {
        if (std.ascii.eqlIgnoreCase(n, s)) return true;
    }
    return false;
}

fn termName(a: Allocator) []const u8 {
    const specifics = [_][2][]const u8{
        .{ "KITTY_WINDOW_ID",     "kitty"     },
        .{ "ALACRITTY_SOCKET",    "alacritty" },
        .{ "ALACRITTY_LOG",       "alacritty" },
        .{ "WEZTERM_UNIX_SOCKET", "wezterm"   },
        .{ "FOOT_SERVER_SOCKET",  "foot"      },
    };
    for (specifics) |p| {
        if (env(a, p[0]).len > 0) return p[1];
    }
    for (&[_][]const u8{ "TERM_PROGRAM", "TERMINAL" }) |k| {
        const v = env(a, k);
        if (v.len > 0) return v;
    }
    const self_status = readFile(a, "/proc/self/status");
    const ppid = parsePPid(self_status);
    if (ppid > 0) {
        const name = trim(procFile(a, "/proc/{d}/comm", ppid));
        if (name.len > 0 and !isShellName(name)) return name;
    }
    return envOr(a, "TERM", "unknown");
}

fn deAndWM(a: Allocator) struct { []const u8, []const u8 } {
    var de: []const u8 = "";
    for (&[_][]const u8{ "XDG_CURRENT_DESKTOP", "DESKTOP_SESSION" }) |k| {
        const v = env(a, k);
        if (v.len > 0) { de = v; break; }
    }
    const standalone = [_][]const u8{
        "hyprland","sway","i3","bspwm","openbox","awesome","dwm",
        "qtile","herbstluftwm","xmonad","river","niri",
    };
    const known = [_][]const u8{
        "kwin_wayland","kwin_x11","mutter","gnome-shell","xfwm4","muffin","marco",
        "hyprland","sway","i3","bspwm","openbox","awesome","dwm",
        "qtile","herbstluftwm","xmonad","river","niri",
    };
    const proc_dir = fs.openDirAbsolute("/proc", .{ .iterate = true }) catch return .{ de, "" };
    var it = proc_dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .directory) continue;
        const comm_path = fmt.allocPrint(a, "/proc/{s}/comm", .{entry.name}) catch continue;
        const name = trim(readFile(a, comm_path));
        if (name.len == 0) continue;
        const is_known = blk: {
            for (known) |k| { if (std.ascii.eqlIgnoreCase(name, k)) break :blk true; }
            break :blk false;
        };
        if (!is_known) continue;
        if (de.len == 0) {
            for (standalone) |s| {
                if (std.ascii.eqlIgnoreCase(name, s)) { de = name; break; }
            }
        }
        return .{ de, name };
    }
    return .{ de, "" };
}

fn localeName(a: Allocator) []const u8 {
    for (&[_][]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" }) |k| {
        const v = env(a, k);
        if (v.len > 0) return v;
    }
    const v = iniLine(readFile(a, "/etc/locale.conf"), "LANG=");
    return if (v.len > 0) v else "unknown";
}

fn cpuInfo(a: Allocator) []const u8 {
    const data  = readFile(a, "/proc/cpuinfo");
    var model: []const u8 = "";
    var cores: usize = 0;
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        if (model.len == 0 and mem.startsWith(u8, line, "model name")) {
            if (mem.indexOfScalar(u8, line, ':')) |ci| {
                var m = trim(line[ci + 1..]);
                m = replaceAll(a, m, "(R)", "");
                m = replaceAll(a, m, "(TM)", "");
                model = m;
            }
        }
        if (mem.startsWith(u8, line, "processor")) cores += 1;
    }
    if (model.len == 0) return "unknown";
    const freq_data = readFile(a, "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq");
    if (freq_data.len > 0) {
        if (fmt.parseFloat(f64, trim(freq_data))) |khz| {
            return fmt.allocPrint(a, "{s} ({d}) @ {d:.2} GHz", .{ model, cores, khz / 1e6 }) catch model;
        } else |_| {}
    }
    return fmt.allocPrint(a, "{s} ({d})", .{ model, cores }) catch model;
}

fn replaceAll(a: Allocator, s: []const u8, needle: []const u8, replacement: []const u8) []const u8 {
    const count = mem.count(u8, s, needle);
    if (count == 0) return s;
    const new_len = s.len - count * needle.len + count * replacement.len;
    const buf = a.alloc(u8, new_len) catch return s;
    _ = mem.replace(u8, s, needle, replacement, buf);
    return buf;
}

const MemVals = struct { total: f64, available: f64, swap_total: f64, swap_free: f64 };

fn memVals(a: Allocator) MemVals {
    const data = readFile(a, "/proc/meminfo");
    var mv = MemVals{ .total = 0, .available = 0, .swap_total = 0, .swap_free = 0 };
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        var f = mem.splitAny(u8, line, " \t");
        var key: []const u8 = "";
        var val: []const u8 = "";
        var i: usize = 0;
        while (f.next()) |tok| {
            if (tok.len == 0) continue;
            if (i == 0) { key = tok; } else if (i == 1) { val = tok; }
            i += 1;
        }
        const v = fmt.parseFloat(f64, val) catch continue;
        if (mem.eql(u8, key, "MemTotal:"))     mv.total      = v;
        if (mem.eql(u8, key, "MemAvailable:")) mv.available  = v;
        if (mem.eql(u8, key, "SwapTotal:"))    mv.swap_total = v;
        if (mem.eql(u8, key, "SwapFree:"))     mv.swap_free  = v;
    }
    return mv;
}

const DiskInfo = struct { label: []const u8, bar: []const u8, fs_type: []const u8 };

fn diskInfo(a: Allocator) DiskInfo {
    const out = run(a, &.{ "df", "-BM", "--output=size,used,fstype", "/" });
    var it = mem.splitScalar(u8, trim(out), '\n');
    _ = it.next();
    const line = it.next() orelse return .{ .label = "unknown", .bar = "", .fs_type = "" };
    var f = mem.splitAny(u8, trim(line), " \t");
    var fields: [3][]const u8 = .{ "", "", "" };
    var i: usize = 0;
    while (f.next()) |tok| {
        if (tok.len == 0) continue;
        if (i < 3) { fields[i] = tok; i += 1; }
    }
    const parse = struct {
        fn p(s: []const u8) f64 {
            return fmt.parseFloat(f64, mem.trimRight(u8, s, "M")) catch 0;
        }
    }.p;
    const total   = parse(fields[0]);
    const used    = parse(fields[1]);
    const fs_type = fields[2];
    const label   = fmt.allocPrint(a, "{d:.1} GiB / {d:.1} GiB",
        .{ used / 1024.0, total / 1024.0 }) catch "unknown";
    return .{ .label = label, .bar = progBar(a, used, total), .fs_type = fs_type };
}

fn localIP(a: Allocator) []const u8 {
    const out = run(a, &.{ "ip", "-4", "addr", "show" });
    var it = mem.splitScalar(u8, out, '\n');
    var iface_name: []const u8 = "";
    while (it.next()) |line| {
        const l = trim(line);
        if (l.len == 0) continue;
        if (l[0] != ' ' and l[0] != '\t') {
            const colon = mem.indexOfScalar(u8, l, ':') orelse continue;
            var f = mem.splitScalar(u8, l[0..colon], ' ');
            _ = f.next();
            const name = trim(f.next() orelse continue);
            if (!mem.eql(u8, name, "lo")) iface_name = name;
            continue;
        }
        if (iface_name.len == 0) continue;
        if (!mem.startsWith(u8, l, "inet ")) continue;
        const after = l[5..];
        const slash = mem.indexOfScalar(u8, after, '/') orelse after.len;
        return fmt.allocPrint(a, "{s} ({s})", .{ after[0..slash], iface_name }) catch "unknown";
    }
    return "unknown";
}

fn gpuList(a: Allocator) [][]const u8 {
    var result: std.ArrayList([]const u8) = .{};
    var nvidia_count: usize = 0;
    const drm_dir = fs.openDirAbsolute("/sys/class/drm", .{ .iterate = true }) catch
        return lspciGPUs(a);
    var drm_it = drm_dir.iterate();
    var seen: std.StringHashMapUnmanaged(void) = .{};
    while (drm_it.next() catch null) |entry| {
        const n = entry.name;
        if (!mem.startsWith(u8, n, "card") or mem.indexOfScalar(u8, n, '-') != null) continue;
        const dev  = fmt.allocPrint(a, "/sys/class/drm/{s}/device", .{n}) catch continue;
        const v    = trim(readFile(a, fmt.allocPrint(a, "{s}/vendor", .{dev}) catch ""));
        const d    = trim(readFile(a, fmt.allocPrint(a, "{s}/device", .{dev}) catch ""));
        if (v.len == 0 or d.len == 0) continue;
        const key  = fmt.allocPrint(a, "{s}:{s}", .{ v, d }) catch continue;
        if (seen.contains(key)) continue;
        seen.put(a, key, {}) catch {};
        if (mem.eql(u8, v, "0x10de")) {
            nvidia_count += 1;
        } else {
            const name = lspciName(a, dev) orelse vendorName(v);
            result.append(a, name) catch {};
        }
    }
    if (nvidia_count > 0) {
        const smi = nvidiaSMI(a);
        if (smi.len > 0) {
            for (smi) |n| result.append(a, n) catch {};
        } else {
            for (0..nvidia_count) |_| result.append(a, "NVIDIA GPU") catch {};
        }
    }
    if (result.items.len == 0) return lspciGPUs(a);
    return result.toOwnedSlice(a) catch &.{};
}

fn nvidiaSMI(a: Allocator) [][]const u8 {
    const out = run(a, &.{ "nvidia-smi", "--query-gpu=name", "--format=csv,noheader,nounits" });
    if (out.len == 0) return &.{};
    var list: std.ArrayList([]const u8) = .{};
    var it = mem.splitScalar(u8, trim(out), '\n');
    while (it.next()) |l| {
        const name = trim(l);
        if (name.len > 0) list.append(a, name) catch {};
    }
    return list.toOwnedSlice(a) catch &.{};
}

fn lspciName(a: Allocator, dev_path: []const u8) ?[]const u8 {
    var buf: [512]u8 = undefined;
    const link = std.fs.readLinkAbsolute(dev_path, &buf) catch return null;
    const addr = fs.path.basename(link);
    const out  = run(a, &.{ "lspci", "-mm" });
    var it = mem.splitScalar(u8, out, '\n');
    while (it.next()) |line| {
        if (!mem.startsWith(u8, line, addr)) continue;
        var count: usize = 0;
        var i: usize = 0;
        while (i < line.len) : (i += 1) {
            if (line[i] != '"') continue;
            count += 1;
            if (count == 11) {
                const start = i + 1;
                i += 1;
                while (i < line.len and line[i] != '"') : (i += 1) {}
                return line[start..i];
            }
        }
    }
    return null;
}

fn vendorName(v: []const u8) []const u8 {
    if (mem.eql(u8, v, "0x1002")) return "AMD GPU";
    if (mem.eql(u8, v, "0x10de")) return "NVIDIA GPU";
    if (mem.eql(u8, v, "0x8086")) return "Intel GPU";
    return "Unknown GPU";
}

fn lspciGPUs(a: Allocator) [][]const u8 {
    const out = run(a, &.{"lspci"});
    var list: std.ArrayList([]const u8) = .{};
    var it = mem.splitScalar(u8, out, '\n');
    while (it.next()) |line| {
        const is_gpu = mem.indexOf(u8, line, "VGA")     != null
                    or mem.indexOf(u8, line, "3D")      != null
                    or mem.indexOf(u8, line, "Display")  != null;
        if (!is_gpu) continue;
        if (mem.indexOf(u8, line, ": ")) |ci|
            list.append(a, trim(line[ci + 2..])) catch {};
    }
    if (list.items.len == 0) list.append(a, "unknown") catch {};
    return list.toOwnedSlice(a) catch &.{};
}

fn monitors(a: Allocator) [][]const u8 {
    const h = hyprMonitors(a);
    if (h.len > 0) return h;
    const x = xrandrMonitors(a);
    if (x.len > 0) return x;
    return drmMonitors(a);
}

fn hyprMonitors(a: Allocator) [][]const u8 {
    const out = run(a, &.{ "hyprctl", "monitors" });
    if (out.len == 0) return &.{};
    var list: std.ArrayList([]const u8) = .{};
    var name: []const u8 = "";
    var it = mem.splitScalar(u8, out, '\n');
    while (it.next()) |raw| {
        const line = trim(raw);
        if (mem.startsWith(u8, line, "Monitor ")) {
            var f = mem.splitScalar(u8, line, ' ');
            _ = f.next();
            name = f.next() orelse "";
            continue;
        }
        if (name.len == 0) continue;
        if (mem.indexOf(u8, line, "@") == null or mem.indexOf(u8, line, "at") == null) continue;
        var f = mem.splitScalar(u8, line, ' ');
        const res_hz = f.next() orelse continue;
        const at_pos = mem.indexOfScalar(u8, res_hz, '@') orelse {
            list.append(a, fmt.allocPrint(a, "{s}: {s}", .{ name, res_hz }) catch "") catch {};
            name = "";
            continue;
        };
        const res    = res_hz[0..at_pos];
        const hz_raw = res_hz[at_pos + 1..];
        const hz_dot = mem.indexOfScalar(u8, hz_raw, '.') orelse hz_raw.len;
        list.append(a, fmt.allocPrint(a, "{s}: {s} @ {s}Hz", .{ name, res, hz_raw[0..hz_dot] }) catch "") catch {};
        name = "";
    }
    return list.toOwnedSlice(a) catch &.{};
}

fn xrandrMonitors(a: Allocator) [][]const u8 {
    const out = run(a, &.{"xrandr"});
    if (out.len == 0) return &.{};
    var list: std.ArrayList([]const u8) = .{};
    var it = mem.splitScalar(u8, out, '\n');
    while (it.next()) |line| {
        if (mem.indexOf(u8, line, " connected") == null) continue;
        if (mem.indexOf(u8, line, "disconnected") != null) continue;
        var f = mem.splitScalar(u8, line, ' ');
        const iface = f.next() orelse continue;
        _ = f.next();
        while (f.next()) |tok| {
            if (mem.indexOf(u8, tok, "x") != null and mem.indexOf(u8, tok, "+") != null) {
                const plus = mem.indexOfScalar(u8, tok, '+') orelse tok.len;
                list.append(a, fmt.allocPrint(a, "{s}: {s}", .{ iface, tok[0..plus] }) catch "") catch {};
                break;
            }
        }
    }
    return list.toOwnedSlice(a) catch &.{};
}

fn drmMonitors(a: Allocator) [][]const u8 {
    var list: std.ArrayList([]const u8) = .{};
    const dir = fs.openDirAbsolute("/sys/class/drm", .{ .iterate = true }) catch {
        list.append(a, "unknown") catch {};
        return list.toOwnedSlice(a) catch &.{};
    };
    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        const n = entry.name;
        if (!mem.startsWith(u8, n, "card") or mem.indexOfScalar(u8, n, '-') == null) continue;
        const base   = fmt.allocPrint(a, "/sys/class/drm/{s}", .{n}) catch continue;
        const status = trim(readFile(a, fmt.allocPrint(a, "{s}/status", .{base}) catch ""));
        if (!mem.eql(u8, status, "connected")) continue;
        const label  = if (mem.indexOfScalar(u8, n, '-')) |i| n[i + 1..] else n;
        const modes  = trim(readFile(a, fmt.allocPrint(a, "{s}/modes", .{base}) catch ""));
        if (modes.len > 0) {
            list.append(a, fmt.allocPrint(a, "{s}: {s}", .{ label, mem.sliceTo(modes, '\n') }) catch "") catch {};
        } else {
            list.append(a, label) catch {};
        }
    }
    if (list.items.len == 0) list.append(a, "unknown") catch {};
    return list.toOwnedSlice(a) catch &.{};
}

fn colorBlocks(a: Allocator) []const u8 {
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(a);
    for (0..8) |i| fmt.format(w, "\x1b[{d}m  ", .{40 + i}) catch {};
    w.writeAll("\x1b[0m  ") catch {};
    for (0..8) |i| fmt.format(w, "\x1b[{d}m  ", .{100 + i}) catch {};
    w.writeAll("\x1b[0m") catch {};
    return buf.toOwnedSlice(a) catch "";
}

fn joinParts(a: Allocator, qt: []const u8, g2: []const u8, g3: []const u8) []const u8 {
    var parts: std.ArrayList([]const u8) = .{};
    if (qt.len > 0) parts.append(a, fmt.allocPrint(a, "{s} [Qt]", .{qt}) catch "") catch {};
    if (g2.len > 0 and mem.eql(u8, g2, g3)) {
        parts.append(a, fmt.allocPrint(a, "{s} [GTK2/3]", .{g2}) catch "") catch {};
    } else {
        if (g2.len > 0) parts.append(a, fmt.allocPrint(a, "{s} [GTK2]", .{g2}) catch "") catch {};
        if (g3.len > 0) parts.append(a, fmt.allocPrint(a, "{s} [GTK3]", .{g3}) catch "") catch {};
    }
    if (parts.items.len == 0) return "unknown";
    return mem.join(a, ", ", parts.items) catch "unknown";
}

fn gtkPair(a: Allocator, key: []const u8, paths_g2: []const []const u8, paths_g3: []const []const u8, de: []const u8, schema: []const u8, gs_key: []const u8) struct { []const u8, []const u8 } {
    var g2: []const u8 = "";
    for (paths_g2) |p| { g2 = gtkFile(a, p, key); if (g2.len > 0) break; }
    if (g2.len == 0 and isGNOME(de)) g2 = gsGet(a, schema, gs_key);
    var g3: []const u8 = "";
    for (paths_g3) |p| { g3 = gtkFile(a, p, key); if (g3.len > 0) break; }
    if (g3.len == 0 and isGNOME(de)) g3 = gsGet(a, schema, gs_key);
    return .{ g2, g3 };
}

fn wmTheme(a: Allocator, de: []const u8) []const u8 {
    if (isKDE(de)) {
        const v1 = kdeGet(a, "kdeglobals", "[KDE]", "widgetStyle");
        if (v1.len > 0) return v1;
        const raw = kdeGet(a, "kwinrc", "[org.kde.kdecoration2]", "theme");
        if (raw.len > 0) {
            var it = mem.splitSequence(u8, raw, "__");
            var last: []const u8 = raw;
            while (it.next()) |p| { if (p.len > 0) last = p; }
            return last;
        }
    }
    if (isGNOME(de)) {
        const v = gsGet(a, "org.gnome.shell.extensions.user-theme", "name");
        if (v.len > 0) return v;
    }
    return "unknown";
}

fn themeInfo(a: Allocator, de: []const u8, home_val: []const u8) []const u8 {
    var qt = kdeGet(a, "kdeglobals", "[General]", "ColorScheme");
    if (qt.len == 0) qt = kdeGet(a, "kdeglobals", "[General]", "widgetStyle");
    const g2p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.gtkrc-2.0", .{home_val}) catch "",
        fmt.allocPrint(a, "{s}/.config/gtk-2.0/gtkrc", .{home_val}) catch "",
    };
    const g3p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.config/gtk-3.0/settings.ini", .{home_val}) catch "",
        "/etc/gtk-3.0/settings.ini",
    };
    const pair = gtkPair(a, "gtk-theme-name", &g2p, &g3p, de, "org.gnome.desktop.interface", "gtk-theme");
    return joinParts(a, qt, pair[0], pair[1]);
}

fn iconsInfo(a: Allocator, de: []const u8, home_val: []const u8) []const u8 {
    var qt: []const u8 = "";
    if (isKDE(de)) qt = kdeGet(a, "kdeglobals", "[Icons]", "Theme");
    const g2p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.gtkrc-2.0", .{home_val}) catch "",
        fmt.allocPrint(a, "{s}/.config/gtk-2.0/gtkrc", .{home_val}) catch "",
    };
    const g3p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.config/gtk-3.0/settings.ini", .{home_val}) catch "",
    };
    const pair = gtkPair(a, "gtk-icon-theme-name", &g2p, &g3p, de, "org.gnome.desktop.interface", "icon-theme");
    return joinParts(a, qt, pair[0], pair[1]);
}

fn fmtFont(a: Allocator, s: []const u8) []const u8 {
    const t = trim(s);
    const sp = mem.lastIndexOfScalar(u8, t, ' ') orelse return t;
    const sz = t[sp + 1..];
    _ = fmt.parseInt(u32, sz, 10) catch return t;
    return fmt.allocPrint(a, "{s} ({s}pt)", .{ t[0..sp], sz }) catch t;
}

fn fontInfo(a: Allocator, de: []const u8, home_val: []const u8) []const u8 {
    var qt: []const u8 = "";
    if (isKDE(de)) {
        const raw = kdeGet(a, "kdeglobals", "[General]", "font");
        if (raw.len > 0) {
            const ci = mem.indexOfScalar(u8, raw, ',') orelse raw.len;
            const name = raw[0..ci];
            if (ci < raw.len) {
                const rest = raw[ci + 1..];
                const ci2  = mem.indexOfScalar(u8, rest, ',') orelse rest.len;
                const size = rest[0..ci2];
                qt = fmt.allocPrint(a, "{s} ({s}pt)", .{ name, size }) catch name;
            } else qt = name;
        }
    }
    const g2p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.gtkrc-2.0", .{home_val}) catch "",
        fmt.allocPrint(a, "{s}/.config/gtk-2.0/gtkrc", .{home_val}) catch "",
    };
    const g3p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.config/gtk-3.0/settings.ini", .{home_val}) catch "",
    };
    const pair = gtkPair(a, "gtk-font-name", &g2p, &g3p, de, "org.gnome.desktop.interface", "font-name");
    return joinParts(a, qt, fmtFont(a, pair[0]), fmtFont(a, pair[1]));
}

fn cursorInfo(a: Allocator, de: []const u8, home_val: []const u8) []const u8 {
    const gtk3 = fmt.allocPrint(a, "{s}/.config/gtk-3.0/settings.ini", .{home_val}) catch "";
    const gtk2 = fmt.allocPrint(a, "{s}/.gtkrc-2.0", .{home_val}) catch "";
    var name: []const u8 = "";
    var size: []const u8 = "";
    if (isKDE(de)) {
        name = kdeGet(a, "kcminputrc", "[Mouse]", "cursorTheme");
        size = kdeGet(a, "kcminputrc", "[Mouse]", "cursorSize");
    }
    if (name.len == 0) name = gtkFile(a, gtk3, "gtk-cursor-theme-name");
    if (size.len == 0) size = gtkFile(a, gtk3, "gtk-cursor-theme-size");
    if (name.len == 0) name = gtkFile(a, gtk2, "gtk-cursor-theme-name");
    if (name.len == 0 and isGNOME(de)) {
        name = gsGet(a, "org.gnome.desktop.interface", "cursor-theme");
        if (size.len == 0) size = gsGet(a, "org.gnome.desktop.interface", "cursor-size");
    }
    if (name.len == 0) {
        const idx = fmt.allocPrint(a, "{s}/.icons/default/index.theme", .{home_val}) catch "";
        const v = iniLine(readFile(a, idx), "Inherits=");
        if (v.len > 0) name = v;
    }
    if (name.len == 0) return "unknown";
    if (size.len > 0 and !mem.eql(u8, size, "0"))
        return fmt.allocPrint(a, "{s} ({s}px)", .{ name, size }) catch name;
    return name;
}

pub fn collect(a: Allocator) Info {
    var info = Info{};
    info.user      = envOr(a, "USER", envOr(a, "LOGNAME", "user"));
    const hn       = trim(readFile(a, "/proc/sys/kernel/hostname"));
    info.hostname  = if (hn.len > 0) hn else "localhost";
    const os_v     = iniLine(readFile(a, "/etc/os-release"), "PRETTY_NAME=");
    info.os        = if (os_v.len > 0) os_v else "CachyOS";
    const ver_data = readFile(a, "/proc/version");
    var ver_it     = mem.splitScalar(u8, ver_data, ' ');
    _ = ver_it.next(); _ = ver_it.next();
    info.kernel    = ver_it.next() orelse "unknown";
    info.uptime    = uptimeStr(a);
    const pkgs     = run(a, &.{ "pacman", "-Q" });
    const pkgs_t   = trim(pkgs);
    if (pkgs_t.len > 0)
        info.packages = fmt.allocPrint(a, "{d} (pacman)", .{mem.count(u8, pkgs_t, "\n") + 1}) catch "unknown";
    const shell_env = env(a, "SHELL");
    info.shell     = if (shell_env.len > 0) fs.path.basename(shell_env) else blk: {
        const self_status = readFile(a, "/proc/self/status");
        const ppid = parsePPid(self_status);
        break :blk trim(procFile(a, "/proc/{d}/comm", ppid));
    };
    info.terminal  = termName(a);
    info.locale    = localeName(a);
    info.cpu       = cpuInfo(a);
    info.gpu       = gpuList(a);
    info.monitors  = monitors(a);
    const dw       = deAndWM(a);
    info.de        = dw[0];
    info.wm        = dw[1];
    const home_val = env(a, "HOME");
    info.wm_theme  = wmTheme(a, info.de);
    info.theme     = themeInfo(a, info.de, home_val);
    info.icons     = iconsInfo(a, info.de, home_val);
    info.font      = fontInfo(a, info.de, home_val);
    info.cursor    = cursorInfo(a, info.de, home_val);
    const mv       = memVals(a);
    const mt       = mv.total / 1024.0;
    const mu       = mt - mv.available / 1024.0;
    info.memory    = fmt.allocPrint(a, "{d:.0} MiB / {d:.0} MiB", .{ mu, mt }) catch "unknown";
    info.mem_bar   = progBar(a, mu, mt);
    if (mv.swap_total > 0) {
        const st = mv.swap_total / 1024.0;
        const su = st - mv.swap_free / 1024.0;
        info.swap     = fmt.allocPrint(a, "{d:.0} MiB / {d:.0} MiB", .{ su, st }) catch "unknown";
        info.swap_bar = progBar(a, su, st);
    }
    const disk     = diskInfo(a);
    info.disk      = disk.label;
    info.disk_bar  = disk.bar;
    info.disk_fs   = disk.fs_type;
    info.local_ip  = localIP(a);
    info.colors    = colorBlocks(a);
    return info;
}
