const std   = @import("std");
const A     = std.mem.Allocator;
const mem   = std.mem;
const fmt   = std.fmt;
const fs    = std.fs;
const linux = std.os.linux;

pub const Info = struct {
    user:     []const u8   = "user",
    hostname: []const u8   = "localhost",
    os:       []const u8   = "CachyOS",
    kernel:   []const u8   = "unknown",
    uptime:   []const u8   = "unknown",
    packages: []const u8   = "unknown",
    shell:    []const u8   = "unknown",
    terminal: []const u8   = "unknown",
    de:       []const u8   = "",
    wm:       []const u8   = "",
    wm_theme: []const u8   = "unknown",
    theme:    []const u8   = "unknown",
    icons:    []const u8   = "unknown",
    font:     []const u8   = "unknown",
    cursor:   []const u8   = "unknown",
    locale:   []const u8   = "unknown",
    cpu:      []const u8   = "unknown",
    gpu:      [][]const u8 = &.{},
    monitors: [][]const u8 = &.{},
    memory:   []const u8   = "unknown",
    mem_bar:  []const u8   = "",
    swap:     []const u8   = "disabled",
    swap_bar: []const u8   = "",
    disk:     []const u8   = "unknown",
    disk_bar: []const u8   = "",
    disk_fs:  []const u8   = "",
    local_ip: []const u8   = "unknown",
    colors:   []const u8   = "",
};

fn readFile(a: A, path: []const u8) []const u8 {
    const f = fs.openFileAbsolute(path, .{}) catch return "";
    defer f.close();
    return f.readToEndAlloc(a, 4 << 20) catch "";
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
    const v = env(a, key);
    return if (v.len > 0) v else fallback;
}

fn trim(s: []const u8) []const u8 {
    return mem.trim(u8, s, " \t\r\n");
}

fn containsLower(s: []const u8, needle: []const u8) bool {
    var i: usize = 0;
    while (i + needle.len <= s.len) : (i += 1)
        if (std.ascii.eqlIgnoreCase(s[i .. i + needle.len], needle)) return true;
    return false;
}

fn isKDE(de: []const u8)   bool { return containsLower(de, "kde") or containsLower(de, "plasma"); }
fn isGNOME(de: []const u8) bool { return containsLower(de, "gnome"); }

fn selfPid() u32 { return @intCast(linux.getpid()); }

fn pidPPid(a: A, pid: u32) u32 {
    const path = fmt.allocPrint(a, "/proc/{d}/status", .{pid}) catch return 0;
    var it = mem.splitScalar(u8, readFile(a, path), '\n');
    while (it.next()) |line|
        if (mem.startsWith(u8, line, "PPid:"))
            return fmt.parseInt(u32, trim(line[5..]), 10) catch 0;
    return 0;
}

fn pidComm(a: A, pid: u32) []const u8 {
    const path = fmt.allocPrint(a, "/proc/{d}/comm", .{pid}) catch return "";
    return trim(readFile(a, path));
}

fn iniLine(data: []const u8, prefix: []const u8) []const u8 {
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |line|
        if (mem.startsWith(u8, line, prefix))
            return mem.trim(u8, line[prefix.len..], "\"");
    return "";
}

fn iniGet(data: []const u8, section: []const u8, key: []const u8) []const u8 {
    var in_sec = section.len == 0;
    var it = mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = trim(raw);
        if (line.len == 0) continue;
        if (line[0] == '[') { in_sec = std.ascii.eqlIgnoreCase(line, section); continue; }
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

fn gsGet(a: A, schema: []const u8, key: []const u8) []const u8 {
    return mem.trim(u8, run(a, &.{ "gsettings", "get", schema, key }), " \t\r\n'\"");
}

fn kdeGet(a: A, home: []const u8, file: []const u8, section: []const u8, key: []const u8) []const u8 {
    const path = fmt.allocPrint(a, "{s}/.config/{s}", .{ home, file }) catch return "";
    return iniGet(readFile(a, path), section, key);
}

fn gtkFile(a: A, path: []const u8, key: []const u8) []const u8 {
    return gtkGet(readFile(a, path), key);
}

fn joinParts(a: A, qt: []const u8, g2: []const u8, g3: []const u8) []const u8 {
    var parts: std.ArrayList([]const u8) = .{};
    if (qt.len > 0) parts.append(a, fmt.allocPrint(a, "{s} [Qt]",     .{qt}) catch "") catch {};
    if (g2.len > 0 and mem.eql(u8, g2, g3)) {
        parts.append(a, fmt.allocPrint(a, "{s} [GTK2/3]", .{g2}) catch "") catch {};
    } else {
        if (g2.len > 0) parts.append(a, fmt.allocPrint(a, "{s} [GTK2]", .{g2}) catch "") catch {};
        if (g3.len > 0) parts.append(a, fmt.allocPrint(a, "{s} [GTK3]", .{g3}) catch "") catch {};
    }
    if (parts.items.len == 0) return "unknown";
    return mem.join(a, ", ", parts.items) catch "unknown";
}

fn gtkPair(a: A, key: []const u8, g2p: []const []const u8, g3p: []const []const u8, de: []const u8, schema: []const u8, gsKey: []const u8) struct { []const u8, []const u8 } {
    var g2: []const u8 = "";
    for (g2p) |p| { g2 = gtkFile(a, p, key); if (g2.len > 0) break; }
    if (g2.len == 0 and isGNOME(de)) g2 = gsGet(a, schema, gsKey);
    var g3: []const u8 = "";
    for (g3p) |p| { g3 = gtkFile(a, p, key); if (g3.len > 0) break; }
    if (g3.len == 0 and isGNOME(de)) g3 = gsGet(a, schema, gsKey);
    return .{ g2, g3 };
}

fn uptimeStr(a: A) []const u8 {
    const secs = fmt.parseFloat(f64, mem.sliceTo(readFile(a, "/proc/uptime"), ' ')) catch return "unknown";
    const t    = @as(u64, @intFromFloat(secs));
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(a);
    if (t / 86400       > 0) fmt.format(w, "{d}d ", .{t / 86400})        catch {};
    if ((t / 3600) % 24 > 0) fmt.format(w, "{d}h ", .{(t / 3600) % 24}) catch {};
    fmt.format(w, "{d}m", .{(t / 60) % 60}) catch {};
    return buf.toOwnedSlice(a) catch "unknown";
}

fn isShellName(n: []const u8) bool {
    for (&[_][]const u8{ "bash","zsh","fish","sh","dash","ksh","tcsh","csh","nushell","nu" }) |s|
        if (std.ascii.eqlIgnoreCase(n, s)) return true;
    return false;
}

fn termName(a: A) []const u8 {
    for (&[_][2][]const u8{
        .{ "KITTY_WINDOW_ID",     "kitty"     },
        .{ "ALACRITTY_SOCKET",    "alacritty" },
        .{ "ALACRITTY_LOG",       "alacritty" },
        .{ "WEZTERM_UNIX_SOCKET", "wezterm"   },
        .{ "FOOT_SERVER_SOCKET",  "foot"      },
        .{ "GHOSTTY_BIN_DIR",     "ghostty"   },
    }) |p| if (env(a, p[0]).len > 0) return p[1];
    for (&[_][]const u8{ "TERM_PROGRAM", "TERMINAL" }) |k| {
        const v = env(a, k);
        if (v.len > 0) return v;
    }
    const term_pid = pidPPid(a, pidPPid(a, selfPid()));
    if (term_pid > 1) {
        const name = pidComm(a, term_pid);
        if (name.len > 0 and !isShellName(name)) return name;
    }
    return "unknown";
}

fn deAndWM(a: A) struct { []const u8, []const u8 } {
    var de: []const u8 = "";
    for (&[_][]const u8{ "XDG_CURRENT_DESKTOP", "DESKTOP_SESSION" }) |k| {
        const v = env(a, k);
        if (v.len > 0) { de = v; break; }
    }
    const standalone = [_][]const u8{ "hyprland","sway","river","niri","openbox","qtile","herbstluftwm" };
    const known_wms  = [_][]const u8{ "kwin_wayland","mutter","gnome-shell","hyprland","sway","river","niri","openbox","qtile","herbstluftwm" };
    const proc_dir = fs.openDirAbsolute("/proc", .{ .iterate = true }) catch return .{ de, "" };
    var it = proc_dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .directory) continue;
        const name = trim(readFile(a, fmt.allocPrint(a, "/proc/{s}/comm", .{entry.name}) catch ""));
        if (name.len == 0) continue;
        const found = for (known_wms) |k| {
            if (std.ascii.eqlIgnoreCase(name, k)) break true;
        } else false;
        if (!found) continue;
        if (de.len == 0) for (standalone) |s|
            if (std.ascii.eqlIgnoreCase(name, s)) { de = name; break; };
        return .{ de, name };
    }
    return .{ de, "" };
}

fn localeName(a: A) []const u8 {
    for (&[_][]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" }) |k| {
        const v = env(a, k);
        if (v.len > 0) return v;
    }
    const v = iniLine(readFile(a, "/etc/locale.conf"), "LANG=");
    return if (v.len > 0) v else "unknown";
}

fn cpuInfo(a: A) []const u8 {
    var model: []const u8 = "";
    var cores: usize = 0;
    var it = mem.splitScalar(u8, readFile(a, "/proc/cpuinfo"), '\n');
    while (it.next()) |line| {
        if (model.len == 0 and mem.startsWith(u8, line, "model name")) {
            if (mem.indexOfScalar(u8, line, ':')) |ci| {
                var m = trim(line[ci + 1..]);
                m = replaceAll(a, m, "(R)",  "");
                m = replaceAll(a, m, "(TM)", "");
                model = trim(m);
            }
        }
        if (mem.startsWith(u8, line, "processor")) cores += 1;
    }
    if (model.len == 0) return "unknown";
    const freq_raw = readFile(a, "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq");
    if (freq_raw.len > 0) {
        if (fmt.parseFloat(f64, trim(freq_raw))) |khz| {
            return fmt.allocPrint(a, "{s} ({d}) @ {d:.2} GHz", .{ model, cores, khz / 1e6 }) catch model;
        } else |_| {}
    }
    return fmt.allocPrint(a, "{s} ({d})", .{ model, cores }) catch model;
}

fn replaceAll(a: A, s: []const u8, needle: []const u8, rep: []const u8) []const u8 {
    const n = mem.count(u8, s, needle);
    if (n == 0) return s;
    const buf = a.alloc(u8, s.len - n * needle.len + n * rep.len) catch return s;
    _ = mem.replace(u8, s, needle, rep, buf);
    return buf;
}

fn memVals(a: A) struct { total: f64, available: f64, swap_total: f64, swap_free: f64 } {
    var mv = std.mem.zeroes(@TypeOf(memVals(undefined)));
    var it = mem.splitScalar(u8, readFile(a, "/proc/meminfo"), '\n');
    while (it.next()) |line| {
        var f = mem.splitAny(u8, line, " \t");
        var key: []const u8 = "";
        var idx: usize = 0;
        var val: f64 = 0;
        while (f.next()) |tok| {
            if (tok.len == 0) continue;
            if (idx == 0) key = tok
            else if (idx == 1) val = fmt.parseFloat(f64, tok) catch 0;
            idx += 1;
        }
        if      (mem.eql(u8, key, "MemTotal:"))     mv.total      = val
        else if (mem.eql(u8, key, "MemAvailable:")) mv.available  = val
        else if (mem.eql(u8, key, "SwapTotal:"))    mv.swap_total = val
        else if (mem.eql(u8, key, "SwapFree:"))     mv.swap_free  = val;
    }
    return mv;
}

fn progBar(a: A, used: f64, total: f64) []const u8 {
    if (total == 0) return "";
    const pct = used / total;
    const n   = @min(@as(usize, @intFromFloat(@round(pct * 20))), 20);
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(a);
    w.writeByte('[') catch {};
    for (0..n)  |_| w.writeAll("█") catch {};
    for (n..20) |_| w.writeAll("░") catch {};
    fmt.format(w, "] {d:.0}%", .{pct * 100.0}) catch {};
    return buf.toOwnedSlice(a) catch "";
}

fn diskInfo(a: A) struct { label: []const u8, bar: []const u8, fs_type: []const u8 } {
    const out = run(a, &.{ "df", "-BM", "--output=size,used,fstype", "/" });
    var it    = mem.splitScalar(u8, trim(out), '\n');
    _ = it.next();
    const line = it.next() orelse return .{ .label = "unknown", .bar = "", .fs_type = "" };
    var fields: [3][]const u8 = .{ "", "", "" };
    var fi: usize = 0;
    var tok_it = mem.splitAny(u8, trim(line), " \t");
    while (tok_it.next()) |tok| {
        if (tok.len == 0) continue;
        if (fi < 3) { fields[fi] = tok; fi += 1; }
    }
    const p = struct { fn f(s: []const u8) f64 { return fmt.parseFloat(f64, mem.trimRight(u8, s, "M")) catch 0; } }.f;
    const total = p(fields[0]);
    const used  = p(fields[1]);
    return .{
        .label   = fmt.allocPrint(a, "{d:.1} GiB / {d:.1} GiB", .{ used / 1024.0, total / 1024.0 }) catch "unknown",
        .bar     = progBar(a, used, total),
        .fs_type = fields[2],
    };
}

fn localIP(a: A) []const u8 {
    var it    = mem.splitScalar(u8, run(a, &.{ "ip", "-4", "addr", "show" }), '\n');
    var iface: []const u8 = "";
    while (it.next()) |raw| {
        if (raw.len == 0) continue;
        if (std.ascii.isDigit(raw[0])) {
            var f = mem.splitScalar(u8, trim(raw), ' ');
            _ = f.next();
            const name = mem.trimRight(u8, f.next() orelse continue, ":");
            iface = if (mem.eql(u8, name, "lo")) "" else name;
        } else if (iface.len > 0) {
            const line = trim(raw);
            if (!mem.startsWith(u8, line, "inet ")) continue;
            const after = line[5..];
            const slash = mem.indexOfScalar(u8, after, '/') orelse after.len;
            return fmt.allocPrint(a, "{s} ({s})", .{ after[0..slash], iface }) catch "unknown";
        }
    }
    return "unknown";
}

fn gpuList(a: A) [][]const u8 {
    var result: std.ArrayList([]const u8)       = .{};
    var seen:   std.StringHashMapUnmanaged(void) = .{};
    var nvidia: usize = 0;
    const drm_dir = fs.openDirAbsolute("/sys/class/drm", .{ .iterate = true }) catch return lspciGPUs(a);
    var drm_it = drm_dir.iterate();
    while (drm_it.next() catch null) |entry| {
        const n = entry.name;
        if (!mem.startsWith(u8, n, "card") or mem.indexOfScalar(u8, n, '-') != null) continue;
        const dev = fmt.allocPrint(a, "/sys/class/drm/{s}/device", .{n}) catch continue;
        const v   = trim(readFile(a, fmt.allocPrint(a, "{s}/vendor", .{dev}) catch ""));
        const d   = trim(readFile(a, fmt.allocPrint(a, "{s}/device", .{dev}) catch ""));
        if (v.len == 0 or d.len == 0) continue;
        const key = fmt.allocPrint(a, "{s}:{s}", .{ v, d }) catch continue;
        if (seen.contains(key)) continue;
        seen.put(a, key, {}) catch {};
        if (mem.eql(u8, v, "0x10de")) {
            nvidia += 1;
        } else {
            result.append(a, lspciName(a, dev) orelse vendorName(v)) catch {};
        }
    }
    if (nvidia > 0) {
        const smi = nvidiaSMI(a);
        if (smi.len > 0) {
            for (smi) |n| result.append(a, n) catch {};
        } else {
            for (0..nvidia) |_| result.append(a, "NVIDIA GPU") catch {};
        }
    }
    if (result.items.len == 0) return lspciGPUs(a);
    return result.toOwnedSlice(a) catch &.{};
}

fn nvidiaSMI(a: A) [][]const u8 {
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

fn lspciName(a: A, dev_path: []const u8) ?[]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const link = std.fs.readLinkAbsolute(dev_path, &buf) catch return null;
    const addr = fs.path.basename(link);
    var it = mem.splitScalar(u8, run(a, &.{ "lspci", "-mm" }), '\n');
    while (it.next()) |line| {
        if (!mem.startsWith(u8, line, addr)) continue;
        var q: usize = 0;
        var i: usize = 0;
        while (i < line.len) : (i += 1) {
            if (line[i] != '"') continue;
            q += 1;
            if (q == 11) {
                const s = i + 1;
                i += 1;
                while (i < line.len and line[i] != '"') : (i += 1) {}
                return line[s..i];
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

fn lspciGPUs(a: A) [][]const u8 {
    var list: std.ArrayList([]const u8) = .{};
    var it = mem.splitScalar(u8, run(a, &.{"lspci"}), '\n');
    while (it.next()) |line| {
        const gpu = mem.indexOf(u8, line, "VGA")     != null
                 or mem.indexOf(u8, line, "3D")      != null
                 or mem.indexOf(u8, line, "Display")  != null;
        if (!gpu) continue;
        if (mem.indexOf(u8, line, ": ")) |ci|
            list.append(a, trim(line[ci + 2..])) catch {};
    }
    if (list.items.len == 0) list.append(a, "unknown") catch {};
    return list.toOwnedSlice(a) catch &.{};
}

// Shared helper: parse "RESxHEIGHT@HZ.dec" → "RES @ HZHz"
// Returns allocated string or null if no @ found (caller appends res only).
fn fmtMode(a: A, name: []const u8, res_hz: []const u8) []const u8 {
    const at = mem.indexOfScalar(u8, res_hz, '@') orelse
        return fmt.allocPrint(a, "{s}: {s}", .{ name, res_hz }) catch "";
    const res    = res_hz[0..at];
    const hz_raw = res_hz[at + 1..];
    const hz_end = mem.indexOfScalar(u8, hz_raw, '.') orelse hz_raw.len;
    return fmt.allocPrint(a, "{s}: {s} @ {s}Hz", .{ name, res, hz_raw[0..hz_end] }) catch "";
}

fn monitors(a: A) [][]const u8 {
    const k = kscreenMonitors(a); if (k.len > 0) return k;
    const h = hyprMonitors(a);    if (h.len > 0) return h;
    const w = wlrMonitors(a);     if (w.len > 0) return w;
    const s = swayMonitors(a);    if (s.len > 0) return s;
    return drmMonitors(a);
}

// kscreen-doctor --outputs (KDE Plasma Wayland)
// Multi-line format:
//   Output: 1 HDMI-A-1 enabled connected
//    Modes:
//     0: 1920x1080@60 *!
//     1: 1920x1080@50
// OR single-line (older):
//   Output: 1 HDMI-A-1 enabled ... Modes: 0:1920x1080@60*! ...
fn kscreenMonitors(a: A) [][]const u8 {
    const out = run(a, &.{ "kscreen-doctor", "--outputs" });
    if (out.len == 0) return &.{};
    var list: std.ArrayList([]const u8) = .{};
    var it   = mem.splitScalar(u8, out, '\n');
    var name: []const u8 = "";
    var in_modes = false;
    while (it.next()) |raw| {
        const line = trim(raw);
        if (line.len == 0) continue;

        if (mem.startsWith(u8, line, "Output:")) {
            name = "";
            in_modes = false;
            if (mem.indexOf(u8, line, "enabled") == null) continue;
            var f = mem.splitScalar(u8, line, ' ');
            _ = f.next(); _ = f.next();
            name = f.next() orelse continue;
            // single-line Modes: on same line?
            if (mem.indexOf(u8, line, "Modes:")) |mp| {
                var mt = mem.splitScalar(u8, trim(line[mp + 6..]), ' ');
                while (mt.next()) |mode| {
                    if (mem.indexOf(u8, mode, "*") == null) continue;
                    const colon = mem.indexOfScalar(u8, mode, ':') orelse continue;
                    var rh = mode[colon + 1..];
                    var end = rh.len;
                    while (end > 0 and !std.ascii.isDigit(rh[end - 1])) end -= 1;
                    list.append(a, fmtMode(a, name, rh[0..end])) catch {};
                    name = "";
                    break;
                }
            }
            continue;
        }

        if (name.len == 0) continue;

        if (mem.eql(u8, line, "Modes:") or mem.startsWith(u8, line, "Modes:")) {
            in_modes = true;
            continue;
        }

        if (in_modes) {
            // multi-line mode entry: "0: 1920x1080@60 *!" or "Mode 0: 1920x1080@60 *!"
            if (mem.indexOf(u8, line, "*") == null) continue;
            const colon = mem.lastIndexOfScalar(u8, line, ':') orelse continue;
            var rh = trim(line[colon + 1..]);
            // strip trailing markers (* !)
            var end = rh.len;
            while (end > 0 and !std.ascii.isDigit(rh[end - 1])) end -= 1;
            rh = rh[0..end];
            list.append(a, fmtMode(a, name, rh)) catch {};
            name = "";
            in_modes = false;
        }
    }
    return list.toOwnedSlice(a) catch &.{};
}

fn hyprMonitors(a: A) [][]const u8 {
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
        if (name.len == 0 or mem.indexOf(u8, line, "@") == null or mem.indexOf(u8, line, " at ") == null) continue;
        list.append(a, fmtMode(a, name, mem.sliceTo(line, ' '))) catch {};
        name = "";
    }
    return list.toOwnedSlice(a) catch &.{};
}

fn wlrMonitors(a: A) [][]const u8 {
    const out = run(a, &.{"wlr-randr"});
    if (out.len == 0) return &.{};
    var list: std.ArrayList([]const u8) = .{};
    var name: []const u8 = "";
    var it = mem.splitScalar(u8, out, '\n');
    while (it.next()) |raw| {
        if (raw.len == 0) continue;
        if (raw[0] != ' ' and raw[0] != '\t') { name = mem.sliceTo(trim(raw), ' '); continue; }
        if (name.len == 0) continue;
        const line = trim(raw);
        if (mem.indexOf(u8, line, " px,") == null or mem.indexOf(u8, line, "current") == null) continue;
        const res      = mem.sliceTo(line, ' ');
        const hz_start = mem.indexOf(u8, line, ", ") orelse continue;
        const hz_rest  = line[hz_start + 2..];
        const hz_end   = mem.indexOf(u8, hz_rest, " Hz") orelse hz_rest.len;
        const hz_dot   = mem.indexOfScalar(u8, hz_rest[0..hz_end], '.') orelse hz_end;
        list.append(a, fmt.allocPrint(a, "{s}: {s} @ {s}Hz", .{ name, res, hz_rest[0..hz_dot] }) catch "") catch {};
        name = "";
    }
    return list.toOwnedSlice(a) catch &.{};
}

fn swayMonitors(a: A) [][]const u8 {
    const out = run(a, &.{ "swaymsg", "-t", "get_outputs" });
    if (out.len == 0) return &.{};
    var list: std.ArrayList([]const u8) = .{};
    var it = mem.splitScalar(u8, out, '\n');
    var cn: []const u8 = ""; var cw: []const u8 = ""; var ch: []const u8 = ""; var chz: []const u8 = "";
    while (it.next()) |raw| {
        const line = trim(raw);
        if (jsonStr(line, "\"name\""))    |v| { cn = v; cw = ""; ch = ""; chz = ""; }
        if (jsonNum(line, "\"width\""))   |v| cw  = v;
        if (jsonNum(line, "\"height\""))  |v| ch  = v;
        if (jsonNum(line, "\"refresh\"")) |v| chz = v;
        if (cn.len > 0 and cw.len > 0 and ch.len > 0 and chz.len > 0) {
            const mhz = fmt.parseInt(u64, chz, 10) catch 0;
            list.append(a, fmt.allocPrint(a, "{s}: {s}x{s} @ {d}Hz", .{ cn, cw, ch, mhz / 1000 }) catch "") catch {};
            cn = ""; cw = ""; ch = ""; chz = "";
        }
    }
    return list.toOwnedSlice(a) catch &.{};
}

fn jsonStr(line: []const u8, key: []const u8) ?[]const u8 {
    const ki    = mem.indexOf(u8, line, key) orelse return null;
    const rest  = line[ki + key.len..];
    const colon = mem.indexOfScalar(u8, rest, ':') orelse return null;
    const after = mem.trimLeft(u8, rest[colon + 1..], " \t");
    if (after.len == 0 or after[0] != '"') return null;
    const end = mem.indexOfScalar(u8, after[1..], '"') orelse return null;
    return after[1 .. 1 + end];
}

fn jsonNum(line: []const u8, key: []const u8) ?[]const u8 {
    const ki    = mem.indexOf(u8, line, key) orelse return null;
    const rest  = line[ki + key.len..];
    const colon = mem.indexOfScalar(u8, rest, ':') orelse return null;
    const after = mem.trimLeft(u8, rest[colon + 1..], " \t");
    var end: usize = 0;
    while (end < after.len and std.ascii.isDigit(after[end])) : (end += 1) {}
    return if (end > 0) after[0..end] else null;
}

fn drmMonitors(a: A) [][]const u8 {
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
        list.append(a, if (modes.len > 0)
            fmt.allocPrint(a, "{s}: {s}", .{ label, mem.sliceTo(modes, '\n') }) catch ""
        else label) catch {};
    }
    if (list.items.len == 0) list.append(a, "unknown") catch {};
    return list.toOwnedSlice(a) catch &.{};
}

fn wmTheme(a: A, de: []const u8, home: []const u8) []const u8 {
    if (isKDE(de)) {
        const v = kdeGet(a, home, "kdeglobals", "[KDE]", "widgetStyle");
        if (v.len > 0) return v;
        const raw = kdeGet(a, home, "kwinrc", "[org.kde.kdecoration2]", "theme");
        if (raw.len > 0) {
            var sp = mem.splitSequence(u8, raw, "__");
            var last: []const u8 = raw;
            while (sp.next()) |p| if (p.len > 0) { last = p; };
            return last;
        }
    }
    if (isGNOME(de)) {
        const v = gsGet(a, "org.gnome.shell.extensions.user-theme", "name");
        if (v.len > 0) return v;
    }
    return "unknown";
}

fn themeInfo(a: A, de: []const u8, home: []const u8) []const u8 {
    var qt = kdeGet(a, home, "kdeglobals", "[General]", "ColorScheme");
    if (qt.len == 0) qt = kdeGet(a, home, "kdeglobals", "[General]", "widgetStyle");
    const g2p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.gtkrc-2.0",            .{home}) catch "",
        fmt.allocPrint(a, "{s}/.config/gtk-2.0/gtkrc", .{home}) catch "",
    };
    const g3p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.config/gtk-3.0/settings.ini", .{home}) catch "",
        "/etc/gtk-3.0/settings.ini",
    };
    const p = gtkPair(a, "gtk-theme-name", &g2p, &g3p, de, "org.gnome.desktop.interface", "gtk-theme");
    return joinParts(a, qt, p[0], p[1]);
}

fn iconsInfo(a: A, de: []const u8, home: []const u8) []const u8 {
    var qt: []const u8 = "";
    if (isKDE(de)) qt = kdeGet(a, home, "kdeglobals", "[Icons]", "Theme");
    const g2p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.gtkrc-2.0",            .{home}) catch "",
        fmt.allocPrint(a, "{s}/.config/gtk-2.0/gtkrc", .{home}) catch "",
    };
    const g3p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.config/gtk-3.0/settings.ini", .{home}) catch "",
    };
    const p = gtkPair(a, "gtk-icon-theme-name", &g2p, &g3p, de, "org.gnome.desktop.interface", "icon-theme");
    return joinParts(a, qt, p[0], p[1]);
}

fn fmtFont(a: A, s: []const u8) []const u8 {
    const t  = trim(s);
    const sp = mem.lastIndexOfScalar(u8, t, ' ') orelse return t;
    const sz = t[sp + 1..];
    _ = fmt.parseInt(u32, sz, 10) catch return t;
    return fmt.allocPrint(a, "{s} ({s}pt)", .{ t[0..sp], sz }) catch t;
}

fn fontInfo(a: A, de: []const u8, home: []const u8) []const u8 {
    var qt: []const u8 = "";
    if (isKDE(de)) {
        const raw = kdeGet(a, home, "kdeglobals", "[General]", "font");
        if (raw.len > 0) {
            const ci = mem.indexOfScalar(u8, raw, ',') orelse raw.len;
            const nm = raw[0..ci];
            if (ci < raw.len) {
                const rest = raw[ci + 1..];
                const ci2  = mem.indexOfScalar(u8, rest, ',') orelse rest.len;
                qt = fmt.allocPrint(a, "{s} ({s}pt)", .{ nm, rest[0..ci2] }) catch nm;
            } else qt = nm;
        }
    }
    const g2p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.gtkrc-2.0",            .{home}) catch "",
        fmt.allocPrint(a, "{s}/.config/gtk-2.0/gtkrc", .{home}) catch "",
    };
    const g3p = [_][]const u8{
        fmt.allocPrint(a, "{s}/.config/gtk-3.0/settings.ini", .{home}) catch "",
    };
    const p = gtkPair(a, "gtk-font-name", &g2p, &g3p, de, "org.gnome.desktop.interface", "font-name");
    return joinParts(a, qt, fmtFont(a, p[0]), fmtFont(a, p[1]));
}

fn cursorInfo(a: A, de: []const u8, home: []const u8) []const u8 {
    const gtk3 = fmt.allocPrint(a, "{s}/.config/gtk-3.0/settings.ini", .{home}) catch "";
    const gtk2 = fmt.allocPrint(a, "{s}/.gtkrc-2.0",                   .{home}) catch "";
    var name: []const u8 = "";
    var size: []const u8 = "";
    if (isKDE(de)) {
        name = kdeGet(a, home, "kcminputrc", "[Mouse]", "cursorTheme");
        size = kdeGet(a, home, "kcminputrc", "[Mouse]", "cursorSize");
    }
    if (name.len == 0) name = gtkFile(a, gtk3, "gtk-cursor-theme-name");
    if (size.len == 0) size = gtkFile(a, gtk3, "gtk-cursor-theme-size");
    if (name.len == 0) name = gtkFile(a, gtk2, "gtk-cursor-theme-name");
    if (name.len == 0 and isGNOME(de)) {
        name = gsGet(a, "org.gnome.desktop.interface", "cursor-theme");
        if (size.len == 0) size = gsGet(a, "org.gnome.desktop.interface", "cursor-size");
    }
    if (name.len == 0) {
        const v = iniLine(readFile(a, fmt.allocPrint(a, "{s}/.icons/default/index.theme", .{home}) catch ""), "Inherits=");
        if (v.len > 0) name = v;
    }
    if (name.len == 0) return "unknown";
    if (size.len > 0 and !mem.eql(u8, size, "0"))
        return fmt.allocPrint(a, "{s} ({s}px)", .{ name, size }) catch name;
    return name;
}

fn colorBlocks(a: A) []const u8 {
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(a);
    for (0..8) |i| fmt.format(w, "\x1b[{d}m  ", .{40 + i}) catch {};
    w.writeAll("\x1b[0m  ") catch {};
    for (0..8) |i| fmt.format(w, "\x1b[{d}m  ", .{100 + i}) catch {};
    w.writeAll("\x1b[0m") catch {};
    return buf.toOwnedSlice(a) catch "";
}

pub fn collect(a: A) Info {
    var info = Info{};
    info.user     = envOr(a, "USER", envOr(a, "LOGNAME", "user"));
    info.hostname = blk: {
        const v = trim(readFile(a, "/proc/sys/kernel/hostname"));
        break :blk if (v.len > 0) v else "localhost";
    };
    info.os = blk: {
        const v = iniLine(readFile(a, "/etc/os-release"), "PRETTY_NAME=");
        break :blk if (v.len > 0) v else "CachyOS";
    };
    info.kernel = blk: {
        var it = mem.splitScalar(u8, readFile(a, "/proc/version"), ' ');
        _ = it.next(); _ = it.next();
        break :blk it.next() orelse "unknown";
    };
    info.uptime   = uptimeStr(a);
    info.packages = blk: {
        const t = trim(run(a, &.{ "pacman", "-Q" }));
        if (t.len == 0) break :blk "unknown";
        break :blk fmt.allocPrint(a, "{d} (pacman)", .{mem.count(u8, t, "\n") + 1}) catch "unknown";
    };
    info.shell = blk: {
        const s = env(a, "SHELL");
        if (s.len > 0) break :blk fs.path.basename(s);
        break :blk pidComm(a, pidPPid(a, selfPid()));
    };
    info.terminal = termName(a);
    info.locale   = localeName(a);
    info.cpu      = cpuInfo(a);
    info.gpu      = gpuList(a);
    info.monitors = monitors(a);
    const dw   = deAndWM(a);
    info.de    = dw[0];
    info.wm    = dw[1];
    const home = env(a, "HOME");
    info.wm_theme = wmTheme(a, info.de, home);
    info.theme    = themeInfo(a, info.de, home);
    info.icons    = iconsInfo(a, info.de, home);
    info.font     = fontInfo(a, info.de, home);
    info.cursor   = cursorInfo(a, info.de, home);
    const mv = memVals(a);
    const mt = mv.total / 1024.0;
    const mu = mt - mv.available / 1024.0;
    info.memory  = fmt.allocPrint(a, "{d:.0} MiB / {d:.0} MiB", .{ mu, mt }) catch "unknown";
    info.mem_bar = progBar(a, mu, mt);
    if (mv.swap_total > 0) {
        const st = mv.swap_total / 1024.0;
        const su = st - mv.swap_free / 1024.0;
        info.swap     = fmt.allocPrint(a, "{d:.0} MiB / {d:.0} MiB", .{ su, st }) catch "unknown";
        info.swap_bar = progBar(a, su, st);
    }
    const disk    = diskInfo(a);
    info.disk     = disk.label;
    info.disk_bar = disk.bar;
    info.disk_fs  = disk.fs_type;
    info.local_ip = localIP(a);
    info.colors   = colorBlocks(a);
    return info;
}
