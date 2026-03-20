const std   = @import("std");
const fetch = @import("fetch");
const mem   = std.mem;
const fmt   = std.fmt;

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
            if (s[i] & 0x80 == 0 or s[i] & 0x40 != 0) n += 1;
            i += 1;
        }
    }
    return n;
}

fn padLogo(a: std.mem.Allocator) [][]const u8 {
    var out: std.ArrayList([]const u8) = .{};
    for (raw_logo) |l| {
        const vl = visLen(l);
        if (vl < logo_width) {
            const pad = a.alloc(u8, logo_width - vl) catch { out.append(a, l) catch {}; continue; };
            @memset(pad, ' ');
            out.append(a, mem.concat(a, u8, &.{ l, pad }) catch l) catch {};
        } else {
            out.append(a, l) catch {};
        }
    }
    return out.toOwnedSlice(a) catch &.{};
}

fn kv(a: std.mem.Allocator, key: []const u8, val: []const u8) []const u8 {
    return fmt.allocPrint(a,
        bold ++ colKey ++ "{s:<10}" ++ reset ++
        " " ++ colSep ++ "─" ++ reset ++
        " " ++ colVal ++ "{s}" ++ reset,
        .{ key, val }) catch "";
}

fn renderBar(a: std.mem.Allocator, b: []const u8) []const u8 {
    const full = "█";
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer(a);
    w.writeAll("            ") catch {};
    var i: usize = 0;
    while (i < b.len) {
        if (i + full.len <= b.len and mem.eql(u8, b[i .. i + full.len], full)) {
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
    return fmt.allocPrint(a, "{s} " ++ colDim ++ "({s})" ++ reset, .{ de, wm }) catch de;
}

fn buildLines(a: std.mem.Allocator, info: fetch.Info) [][]const u8 {
    var lines: std.ArrayList([]const u8) = .{};

    // header: user@hostname
    lines.append(a, fmt.allocPrint(a,
        bold ++ colKey ++ "{s}" ++ reset ++
        colSep ++ "@" ++ reset ++
        bold ++ colKey ++ "{s}" ++ reset,
        .{ info.user, info.hostname }) catch "") catch {};

    // divider
    const div_len = info.user.len + 1 + info.hostname.len;
    var div: std.ArrayList(u8) = .{};
    div.writer(a).writeAll(colKey) catch {};
    for (0..div_len) |_| div.writer(a).writeAll("─") catch {};
    div.writer(a).writeAll(reset) catch {};
    lines.append(a, div.toOwnedSlice(a) catch "") catch {};

    lines.append(a, kv(a, "OS",       info.os))       catch {};
    lines.append(a, kv(a, "Kernel",   info.kernel))   catch {};
    lines.append(a, kv(a, "Uptime",   info.uptime))   catch {};
    lines.append(a, kv(a, "Packages", info.packages)) catch {};
    lines.append(a, kv(a, "Shell",    info.shell))    catch {};
    lines.append(a, kv(a, "Terminal", info.terminal)) catch {};
    lines.append(a, kv(a, "WM/DE",    dewm(a, info.de, info.wm))) catch {};
    lines.append(a, kv(a, "WM Theme", info.wm_theme)) catch {};
    lines.append(a, kv(a, "Theme",    info.theme))    catch {};
    lines.append(a, kv(a, "Icons",    info.icons))    catch {};
    lines.append(a, kv(a, "Font",     info.font))     catch {};
    lines.append(a, kv(a, "Cursor",   info.cursor))   catch {};
    lines.append(a, kv(a, "Locale",   info.locale))   catch {};
    lines.append(a, kv(a, "CPU",      info.cpu))      catch {};

    for (info.gpu, 0..) |g, i|
        lines.append(a, kv(a, if (i == 0) "GPU" else "", g)) catch {};
    for (info.monitors, 0..) |m, i|
        lines.append(a, kv(a, if (i == 0) "Monitor" else "", m)) catch {};

    lines.append(a, kv(a, "Memory", info.memory))    catch {};
    lines.append(a, renderBar(a, info.mem_bar))       catch {};
    lines.append(a, kv(a, "Swap", info.swap))         catch {};
    if (info.swap_bar.len > 0)
        lines.append(a, renderBar(a, info.swap_bar))  catch {};

    const disk_val = if (info.disk_fs.len > 0)
        fmt.allocPrint(a, "{s}  " ++ colFS ++ "[{s}]" ++ reset,
            .{ info.disk, info.disk_fs }) catch info.disk
    else info.disk;
    lines.append(a, kv(a, "Disk",     disk_val))      catch {};
    lines.append(a, renderBar(a, info.disk_bar))       catch {};
    lines.append(a, kv(a, "Local IP", info.local_ip)) catch {};
    lines.append(a, "")                                catch {};
    lines.append(a, fmt.allocPrint(a, "            {s}", .{info.colors}) catch "") catch {};

    return lines.toOwnedSlice(a) catch &.{};
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const info  = fetch.collect(a);
    const left  = padLogo(a);
    const right = buildLines(a, info);
    const pad   = try a.alloc(u8, logo_width);
    @memset(pad, ' ');

    var out: std.ArrayList(u8) = .{};
    const w = out.writer(a);
    const n = @max(left.len, right.len);
    for (0..n) |i| {
        const l = if (i < left.len)  left[i]  else pad;
        const r = if (i < right.len) right[i] else "";
        fmt.format(w, "{s}   {s}\n", .{ l, r }) catch {};
    }
    w.writeByte('\n') catch {};

    _ = try std.posix.write(std.posix.STDOUT_FILENO, out.items);
}
