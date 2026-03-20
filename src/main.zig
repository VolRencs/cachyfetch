const std   = @import("std");
const fetch = @import("fetch");
const mem  = std.mem;
const fmt  = std.fmt;

const reset  = "\x1b[0m";
const bold   = "\x1b[1m";
const c1     = "\x1b[38;5;81m";
const c2     = "\x1b[38;5;117m";
const c3     = "\x1b[38;5;153m";
const colKey = "\x1b[38;5;81m";
const colSep = "\x1b[38;5;240m";
const colVal = "\x1b[38;5;253m";
const colBar = "\x1b[38;5;81m";
const colFS  = "\x1b[38;5;240m";

const logo_width = 36;

const raw_logo = [_][]const u8{
    c1 ++ "        ................." ++ reset,
    c1 ++ "       .................." ++ reset,
    c1 ++ "      ..................." ++ c3 ++ "   ..." ++ reset,
    c1 ++ "      .................." ++ c3 ++ "   ...." ++ reset,
    c1 ++ "      ................." ++ c3 ++ "   ......" ++ reset,
    c1 ++ "     .................." ++ c3 ++ "   ....." ++ reset,
    c1 ++ "    .................." ++ c3 ++ "      ..." ++ reset,
    c1 ++ "    ................." ++ reset,
    c2 ++ "   ........." ++ reset,
    c2 ++ "   ........" ++ reset,
    c2 ++ "  ........." ++ c3 ++ "             .." ++ reset,
    c2 ++ " ........." ++ c3 ++ "            ....." ++ reset,
    c2 ++ " ........." ++ c3 ++ "            ......" ++ reset,
    c2 ++ "........." ++ c3 ++ "            ......." ++ reset,
    c2 ++ "........." ++ c3 ++ "             ......" ++ reset,
    c2 ++ " ........" ++ c3 ++ "             ......" ++ reset,
    c2 ++ " ........." ++ c3 ++ "             ...." ++ reset,
    c2 ++ "  ........" ++ reset,
    c2 ++ "  ........." ++ reset,
    c1 ++ "   ........" ++ c3 ++ "                  ." ++ reset,
    c1 ++ "   ........." ++ c3 ++ "              ......" ++ reset,
    c1 ++ "    .................." ++ c3 ++ "   ........" ++ reset,
    c1 ++ "     ................." ++ c3 ++ "  .........." ++ reset,
    c1 ++ "     ................" ++ c3 ++ "   .........." ++ reset,
    c1 ++ "      ..............." ++ c3 ++ "   .........." ++ reset,
    c1 ++ "      ................" ++ c3 ++ "  .........." ++ reset,
    c1 ++ "       ..............." ++ c3 ++ "  .........." ++ reset,
    c1 ++ "       ................" ++ c3 ++ "  ........" ++ reset,
    c1 ++ "        .............." ++ c3 ++ "    ......" ++ reset,
    c3 ++ "                            ." ++ reset,
    "",
};

fn visLen(s: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == 0x1b and i + 1 < s.len and s[i + 1] == '[') {
            i += 2;
            while (i < s.len and (std.ascii.isDigit(s[i]) or s[i] == ';')) : (i += 1) {}
            if (i < s.len and s[i] == 'm') i += 1;
        } else {
            n += 1;
            i += 1;
        }
    }
    return n;
}

fn logo(a: std.mem.Allocator) [][]const u8 {
    var out = a.alloc([]const u8, raw_logo.len) catch return &.{};
    for (raw_logo, 0..) |l, i| {
        const vl = visLen(l);
        if (vl < logo_width) {
            const pad = a.alloc(u8, logo_width - vl) catch { out[i] = l; continue; };
            @memset(pad, ' ');
            out[i] = mem.concat(a, u8, &.{ l, pad }) catch l;
        } else {
            out[i] = l;
        }
    }
    return out;
}

fn kv(a: std.mem.Allocator, key: []const u8, val: []const u8) []const u8 {
    return fmt.allocPrint(a,
        bold ++ colKey ++ "{s:<10}" ++ reset ++ " " ++ colSep ++ "─" ++ reset ++ " " ++ colVal ++ "{s}" ++ reset,
        .{ key, val }) catch "";
}

fn colorBar(a: std.mem.Allocator, b: []const u8) []const u8 {
    const full = "█";
    var buf = std.ArrayList(u8).init(a);
    buf.appendSlice("            ") catch {};
    var i: usize = 0;
    while (i < b.len) {
        if (i + full.len <= b.len and mem.eql(u8, b[i .. i + full.len], full)) {
            buf.appendSlice(colBar ++ "█" ++ reset) catch {};
            i += full.len;
        } else {
            buf.append(b[i]) catch {};
            i += 1;
        }
    }
    return buf.toOwnedSlice() catch "";
}

fn dewm(a: std.mem.Allocator, de: []const u8, wm: []const u8) []const u8 {
    if (de.len == 0 and wm.len == 0) return "unknown";
    if (de.len == 0) return wm;
    if (wm.len == 0 or std.ascii.eqlIgnoreCase(de, wm)) return de;
    return fmt.allocPrint(a, "{s} ({s})", .{ de, wm }) catch de;
}

fn infoLines(a: std.mem.Allocator, info: fetch.Info) [][]const u8 {
    var lines = std.ArrayList([]const u8).init(a);
    const app = struct {
        fn f(l: *std.ArrayList([]const u8), s: []const u8) void { l.append(s) catch {}; }
    }.f;

    const header = fmt.allocPrint(a,
        bold ++ colKey ++ "{s}" ++ reset ++ colSep ++ "@" ++ reset ++ bold ++ colKey ++ "{s}" ++ reset,
        .{ info.user, info.hostname }) catch "";
    app(&lines, header);

    const div_len = info.user.len + 1 + info.hostname.len;
    const div_buf = a.alloc(u8, div_len) catch &.{};
    @memset(div_buf, 0xe2); // placeholder; build proper divider
    const divider = blk: {
        var b = std.ArrayList(u8).init(a);
        b.appendSlice(colKey) catch {};
        for (0..div_len) |_| b.appendSlice("─") catch {};
        b.appendSlice(reset) catch {};
        break :blk b.toOwnedSlice() catch "";
    };
    _ = div_buf;
    app(&lines, divider);

    app(&lines, kv(a, "OS",       info.os));
    app(&lines, kv(a, "Kernel",   info.kernel));
    app(&lines, kv(a, "Uptime",   info.uptime));
    app(&lines, kv(a, "Packages", info.packages));
    app(&lines, kv(a, "Shell",    info.shell));
    app(&lines, kv(a, "Terminal", info.terminal));
    app(&lines, kv(a, "WM/DE",    dewm(a, info.de, info.wm)));
    app(&lines, kv(a, "WM Theme", info.wm_theme));
    app(&lines, kv(a, "Theme",    info.theme));
    app(&lines, kv(a, "Icons",    info.icons));
    app(&lines, kv(a, "Font",     info.font));
    app(&lines, kv(a, "Cursor",   info.cursor));
    app(&lines, kv(a, "Locale",   info.locale));
    app(&lines, kv(a, "CPU",      info.cpu));

    for (info.gpu, 0..) |g, i| {
        app(&lines, kv(a, if (i == 0) "GPU" else "", g));
    }
    for (info.monitors, 0..) |m, i| {
        app(&lines, kv(a, if (i == 0) "Monitor" else "", m));
    }

    app(&lines, kv(a, "Memory", info.memory));
    app(&lines, colorBar(a, info.mem_bar));
    app(&lines, kv(a, "Swap", info.swap));
    if (info.swap_bar.len > 0) app(&lines, colorBar(a, info.swap_bar));

    const disk_val = if (info.disk_fs.len > 0)
        fmt.allocPrint(a, "{s}  " ++ colFS ++ "[{s}]" ++ reset, .{ info.disk, info.disk_fs }) catch info.disk
    else
        info.disk;
    app(&lines, kv(a, "Disk",     disk_val));
    app(&lines, colorBar(a, info.disk_bar));
    app(&lines, kv(a, "Local IP", info.local_ip));
    app(&lines, "");
    app(&lines, fmt.allocPrint(a, "            {s}", .{info.colors}) catch "");

    return lines.toOwnedSlice() catch &.{};
}

pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const a = gpa.allocator();

    const info   = fetch.collect(a);
    const left   = logo(a);
    const right  = infoLines(a, info);
    const pad    = try a.alloc(u8, logo_width);
    @memset(pad, ' ');

    const stdout = std.io.getStdOut().writer();
    const total  = @max(left.len, right.len);

    for (0..total) |i| {
        const l = if (i < left.len)  left[i]  else pad;
        const r = if (i < right.len) right[i] else "";
        try stdout.print("{s}   {s}\n", .{ l, r });
    }
    try stdout.writeByte('\n');
}
