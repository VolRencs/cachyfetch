package main

import (
	"fmt"
	"strings"
)

const (
	reset  = "\x1b[0m"
	bold   = "\x1b[1m"
	c1     = "\x1b[38;5;81m"
	c2     = "\x1b[38;5;117m"
	c3     = "\x1b[38;5;153m"
	colKey = "\x1b[38;5;81m"
	colSep = "\x1b[38;5;240m"
	colVal = "\x1b[38;5;253m"
	colBar = "\x1b[38;5;81m"
	colFS  = "\x1b[38;5;240m"

	logoWidth = 36
)

func stripANSI(s string) string {
	var b strings.Builder
	b.Grow(len(s))

	for i := 0; i < len(s); i++ {
		if s[i] == 0x1b && i+1 < len(s) && s[i+1] == '[' {
			i += 2
			for i < len(s) && ((s[i] >= '0' && s[i] <= '9') || s[i] == ';') {
				i++
			}
			if i < len(s) && s[i] == 'm' {
				continue
			}
		}
		b.WriteByte(s[i])
	}

	return b.String()
}

func visLen(s string) int { return len(stripANSI(s)) }

var rawLogo = []string{
	c1 + `        .................` + reset,
	c1 + `       ..................` + reset,
	c1 + `      ...................` + c3 + `   ...` + reset,
	c1 + `      ..................` + c3 + `   ....` + reset,
	c1 + `      .................` + c3 + `   ......` + reset,
	c1 + `     ..................` + c3 + `   .....` + reset,
	c1 + `    ..................` + c3 + `      ...` + reset,
	c1 + `    .................` + reset,
	c2 + `   .........` + reset,
	c2 + `   ........` + reset,
	c2 + `  .........` + c3 + `             ..` + reset,
	c2 + ` .........` + c3 + `            .....` + reset,
	c2 + ` .........` + c3 + `            ......` + reset,
	c2 + `.........` + c3 + `            .......` + reset,
	c2 + `.........` + c3 + `             ......` + reset,
	c2 + ` ........` + c3 + `             ......` + reset,
	c2 + ` .........` + c3 + `             ....` + reset,
	c2 + `  ........` + reset,
	c2 + `  .........` + reset,
	c1 + `   ........` + c3 + `                  .` + reset,
	c1 + `   .........` + c3 + `              ......` + reset,
	c1 + `    ..................` + c3 + `   ........` + reset,
	c1 + `     .................` + c3 + `  ..........` + reset,
	c1 + `     ................` + c3 + `   ..........` + reset,
	c1 + `      ...............` + c3 + `   ..........` + reset,
	c1 + `      ................` + c3 + `  ..........` + reset,
	c1 + `       ...............` + c3 + `  ..........` + reset,
	c1 + `       ................` + c3 + `  ........` + reset,
	c1 + `        ..............` + c3 + `    ......` + reset,
	c3 + `                            .` + reset,
	``,
}

func logo() []string {
	out := make([]string, len(rawLogo))
	for i, l := range rawLogo {
		if d := logoWidth - visLen(l); d > 0 {
			out[i] = l + strings.Repeat(" ", d)
		} else {
			out[i] = l
		}
	}
	return out
}

func kv(key, val string) string {
	return fmt.Sprintf("%s%s%-10s%s %s─%s %s%s%s",
		bold, colKey, key, reset, colSep, reset, colVal, val, reset)
}

func bar(b string) string {
	return "            " + strings.ReplaceAll(b, "█", colBar+"█"+reset)
}

func dewm(de, wm string) string {
	switch {
	case de == "" && wm == "":
		return "unknown"
	case de == "":
		return wm
	case wm == "" || strings.EqualFold(de, wm):
		return de
	default:
		return de + " (" + wm + ")"
	}
}

func multi(key string, vals []string) []string {
	out := make([]string, len(vals))
	for i, v := range vals {
		if i == 0 {
			out[i] = kv(key, v)
		} else {
			out[i] = kv("", v)
		}
	}
	return out
}

func infoLines(info Info) []string {
	header := fmt.Sprintf("%s%s%s%s@%s%s%s",
			      bold+colKey, info.User, reset+colSep,
		       reset+bold+colKey, info.Hostname, reset, reset)
	divider := colKey + strings.Repeat("─", len(info.User)+1+len(info.Hostname)) + reset

	diskVal := info.Disk
	if info.DiskFS != "" {
		diskVal += "  " + colFS + "[" + info.DiskFS + "]" + reset
	}

	lines := []string{
		header, divider,
		kv("OS", info.OS),
		kv("Kernel", info.Kernel),
		kv("Uptime", info.Uptime),
		kv("Packages", info.Packages),
		kv("Shell", info.Shell),
		kv("Terminal", info.Terminal),
		kv("WM/DE", dewm(info.DE, info.WM)),
		kv("WM Theme", info.WMTheme),
		kv("Theme", info.Theme),
		kv("Icons", info.Icons),
		kv("Font", info.Font),
		kv("Cursor", info.Cursor),
		kv("Locale", info.Locale),
		kv("CPU", info.CPU),
	}
	lines = append(lines, multi("GPU", info.GPU)...)
	lines = append(lines, multi("Monitor", info.Monitors)...)
	lines = append(lines, kv("Memory", info.Memory), bar(info.MemBar))
	lines = append(lines, kv("Swap", info.Swap))
	if info.SwapBar != "" {
		lines = append(lines, bar(info.SwapBar))
	}
	return append(lines,
		      kv("Disk", diskVal), bar(info.DiskBar),
		      kv("Local IP", info.LocalIP),
		      "", "            "+info.Colors)
}
