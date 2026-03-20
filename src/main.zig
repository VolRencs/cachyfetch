const std = @import("std");
const core = @import("core.zig");

const reset = "\x1b[0m";
const bold = "\x1b[1m";
const c1 = "\x1b[38;5;81m";
const c2 = "\x1b[38;5;117m";
const c3 = "\x1b[38;5;153m";
const colKey = "\x1b[38;5;81m";
const colSep = "\x1b[38;5;240m";
const colVal = "\x1b[38;5;253m";
const colBar = "\x1b[38;5;81m";
const colFS = "\x1b[38;5;240m";
const colDim = "\x1b[38;5;240m";

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
            // UTF-8: count only leading bytes as characters
            if ((s[i] & 0x80) == 0 or (s[i] & 0x40) != 0) n += 1;
            i += 1;
        }
    }
    return n;
}

fn padLogo(a: std.mem.Allocator) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (raw_logo) |l| {
        const vl = visLen(l);
        if (vl < logo_width) {
            const pad_len = logo_width - vl;
            const pad = try a.alloc(u8, pad_len);
            @memset(pad, ' ');
            const combined = try std.mem.concat(a, u8, &.{ l, pad });
            a.free(pad);
            try out.append(a, combined);
        } else {
            try out.append(a, l);
        }
    }
    return out.toOwnedSlice(a);
}

fn kv(a: std.mem.Allocator, key: []const u8, val: []const u8) []const u8 {
    return std.fmt.allocPrint(
        a,
        bold ++ colKey ++ "{s:<10}" ++ reset ++ " " ++ colSep ++ "─" ++ reset ++ " " ++ colVal ++ "{s}" ++ reset,
        .{ key, val },
    ) catch "";
}

fn renderBar(a: std.mem.Allocator, b: []const u8) []const u8 {
    const full = "█";
    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(a);
    w.writeAll("            ") catch {};
    var i: usize = 0;
    while (i < b.len) {
        if (i + full.len <= b.len and std.mem.eql(u8, b[i .. i + full.len], full)) {
            w.writeAll(colBar ++ "█" ++ reset) catch {};
            i += full.len;
        } else {
            w.writeByte(b[i]) catch {};
            i += 1;
        }
    }
    return buf.toOwnedSlice(a) catch "";
}

fn dewm(a: std.mem.Allocator, de: []const u8, wm: []const u8) []const u8 {
    if (de.len == 0 and wm.len == 0) return "unknown";
    if (de.len == 0) return wm;
    if (wm.len == 0 or std.ascii.eqlIgnoreCase(de, wm)) return de;
    return std.fmt.allocPrint(a, "{s} " ++ colDim ++ "({s})" ++ reset, .{ de, wm }) catch de;
}

fn appendLine(lines: *std.ArrayList([]const u8), a: std.mem.Allocator, line: []const u8) void {
    lines.append(a, line) catch {};
}

fn appendKV(lines: *std.ArrayList([]const u8), a: std.mem.Allocator, key: []const u8, val: []const u8) void {
    appendLine(lines, a, kv(a, key, val));
}

fn appendList(lines: *std.ArrayList([]const u8), a: std.mem.Allocator, key: []const u8, values: [][]const u8) void {
    for (values, 0..) |value, i| {
        appendKV(lines, a, if (i == 0) key else "", value);
    }
}

fn buildLines(a: std.mem.Allocator, info: core.Info) [][]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    const header = std.fmt.allocPrint(
        a,
        bold ++ colKey ++ "{s}" ++ reset ++ colSep ++ "@" ++ reset ++ bold ++ colKey ++ "{s}" ++ reset,
        .{ info.user, info.hostname },
    ) catch "";
    appendLine(&lines, a, header);

    const header_vis = visLen(info.user) + 1 + visLen(info.hostname);
    var divider: std.ArrayList(u8) = .empty;
    const divider_writer = divider.writer(a);
    divider_writer.writeAll(colKey) catch {};
    for (0..header_vis) |_| divider_writer.writeAll("─") catch {};
    divider_writer.writeAll(reset) catch {};
    appendLine(&lines, a, divider.toOwnedSlice(a) catch "");

    appendKV(&lines, a, "OS", info.os);
    appendKV(&lines, a, "Kernel", info.kernel);
    appendKV(&lines, a, "Uptime", info.uptime);
    appendKV(&lines, a, "Packages", info.packages);
    appendKV(&lines, a, "Shell", info.shell);
    appendKV(&lines, a, "Terminal", info.terminal);
    appendKV(&lines, a, "WM/DE", dewm(a, info.de, info.wm));
    appendKV(&lines, a, "WM Theme", info.wm_theme);
    appendKV(&lines, a, "Theme", info.theme);
    appendKV(&lines, a, "Icons", info.icons);
    appendKV(&lines, a, "Font", info.font);
    appendKV(&lines, a, "Cursor", info.cursor);
    appendKV(&lines, a, "Locale", info.locale);
    appendKV(&lines, a, "CPU", info.cpu);
    appendList(&lines, a, "GPU", info.gpu);
    appendList(&lines, a, "Monitor", info.monitors);
    appendKV(&lines, a, "Memory", info.memory);
    appendLine(&lines, a, renderBar(a, info.mem_bar));
    appendKV(&lines, a, "Swap", info.swap);
    if (info.swap_bar.len > 0) appendLine(&lines, a, renderBar(a, info.swap_bar));

    const disk_value = if (info.disk_fs.len > 0)
        std.fmt.allocPrint(a, "{s}  " ++ colFS ++ "[{s}]" ++ reset, .{ info.disk, info.disk_fs }) catch info.disk
    else
        info.disk;
    appendKV(&lines, a, "Disk", disk_value);
    appendLine(&lines, a, renderBar(a, info.disk_bar));
    appendKV(&lines, a, "Local IP", info.local_ip);
    appendLine(&lines, a, "");
    appendLine(&lines, a, std.fmt.allocPrint(a, "            {s}", .{info.colors}) catch "");

    return lines.toOwnedSlice(a) catch &.{};
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const info = core.collect(a);

    const left = try padLogo(a);
    const right = buildLines(a, info);

    const pad = try a.alloc(u8, logo_width);
    @memset(pad, ' ');

    var out: std.ArrayList(u8) = .empty;
    const w = out.writer(a);
    const n = @max(left.len, right.len);
    for (0..n) |i| {
        const l = if (i < left.len) left[i] else pad;
        const r = if (i < right.len) right[i] else "";
        std.fmt.format(w, "{s}   {s}\n", .{ l, r }) catch {};
    }
    w.writeByte('\n') catch {};

    _ = try std.posix.write(std.posix.STDOUT_FILENO, out.items);

    a.free(pad);
}
