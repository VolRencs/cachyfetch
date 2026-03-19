package main

import (
	"bufio"
	"fmt"
	"math"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Info struct {
	User, Hostname      string
	OS, Kernel, Uptime  string
	Packages, Shell     string
	Terminal, DE, WM    string
	WMTheme, Theme      string
	Icons, Font, Cursor string
	Locale, CPU         string
	GPU, Monitors       []string
	Memory, MemBar      string
	Swap, SwapBar       string
	Disk, DiskBar       string
	DiskFS, LocalIP     string
	Colors              string
}

var home = os.Getenv("HOME")

func collect() (i Info) {
	i.Hostname, _ = os.Hostname()
	if i.Hostname == "" {
		i.Hostname = "localhost"
	}
	i.User              = envOr("USER", envOr("LOGNAME", "user"))
	i.OS                = iniLine("/etc/os-release", "PRETTY_NAME=")
	i.Kernel            = kernelVer()
	i.Uptime            = uptime()
	i.Packages          = packages()
	i.Shell             = shellName()
	i.Terminal          = termName()
	i.Locale            = locale()
	i.CPU               = cpuInfo()
	i.GPU               = gpuList()
	i.Monitors          = monitors()
	i.DE, i.WM          = deAndWM()
	i.WMTheme           = wmTheme(i.DE)
	i.Theme             = themeInfo(i.DE)
	i.Icons             = iconsInfo(i.DE)
	i.Font              = fontInfo(i.DE)
	i.Cursor            = cursorInfo(i.DE)
	i.Memory, i.MemBar  = memInfo()
	i.Swap, i.SwapBar   = swapInfo()
	i.Disk, i.DiskBar, i.DiskFS = diskInfo()
	i.LocalIP           = localIP()
	i.Colors            = colorBlocks()
	return
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func iniLine(path, prefix string) string {
	data, _ := os.ReadFile(path)
	for _, l := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(l, prefix) {
			return strings.Trim(l[len(prefix):], `"`)
		}
	}
	return ""
}

func kernelVer() string {
	data, _ := os.ReadFile("/proc/version")
	if f := strings.Fields(string(data)); len(f) >= 3 {
		return f[2]
	}
	return "unknown"
}

func uptime() string {
	data, _ := os.ReadFile("/proc/uptime")
	secs, _ := strconv.ParseFloat(strings.Fields(string(data))[0], 64)
	d := time.Duration(secs) * time.Second
	h := int(d.Hours())
	days, hrs, mins := h/24, h%24, int(d.Minutes())%60
	var p []string
	if days > 0 {
		p = append(p, fmt.Sprintf("%dd", days))
	}
	if hrs > 0 {
		p = append(p, fmt.Sprintf("%dh", hrs))
	}
	return strings.Join(append(p, fmt.Sprintf("%dm", mins)), " ")
}

func packages() string {
	out, err := exec.Command("pacman", "-Q").Output()
	s := strings.TrimSpace(string(out))
	if err != nil || s == "" {
		return "unknown"
	}
	return fmt.Sprintf("%d (pacman)", strings.Count(s, "\n")+1)
}

func shellName() string {
	if s := os.Getenv("SHELL"); s != "" {
		return filepath.Base(s)
	}
	data, _ := os.ReadFile(fmt.Sprintf("/proc/%d/comm", os.Getppid()))
	return strings.TrimSpace(string(data))
}

func termName() string {
	for _, p := range [][2]string{
		{"KITTY_WINDOW_ID", "kitty"},
		{"ALACRITTY_SOCKET", "alacritty"}, {"ALACRITTY_LOG", "alacritty"},
		{"WEZTERM_UNIX_SOCKET", "wezterm"},
		{"FOOT_SERVER_SOCKET", "foot"},
	} {
		if os.Getenv(p[0]) != "" {
			return p[1]
		}
	}
	for _, k := range []string{"TERM_PROGRAM", "TERMINAL"} {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	if ppid := ppidOf(os.Getppid()); ppid > 0 {
		if n := comm(ppid); n != "" && !isShell(n) {
			return n
		}
	}
	return envOr("TERM", "unknown")
}

func ppidOf(pid int) int {
	data, _ := os.ReadFile(fmt.Sprintf("/proc/%d/status", pid))
	for _, l := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(l, "PPid:") {
			v, _ := strconv.Atoi(strings.TrimSpace(l[5:]))
			return v
		}
	}
	return 0
}

func comm(pid int) string {
	data, _ := os.ReadFile(fmt.Sprintf("/proc/%d/comm", pid))
	return strings.TrimSpace(string(data))
}

func isShell(n string) bool {
	switch strings.ToLower(n) {
	case "bash", "zsh", "fish", "sh", "dash", "ksh", "tcsh", "csh":
		return true
	}
	return false
}

func deAndWM() (de, wm string) {
	for _, k := range []string{"XDG_CURRENT_DESKTOP", "DESKTOP_SESSION"} {
		if v := os.Getenv(k); v != "" {
			de = v
			break
		}
	}
	standalone := map[string]bool{
		"hyprland": true, "sway": true, "i3": true, "bspwm": true,
		"openbox": true, "awesome": true, "dwm": true, "qtile": true,
		"herbstluftwm": true, "xmonad": true, "river": true, "niri": true,
	}
	known := map[string]bool{
		"kwin_wayland": true, "kwin_x11": true, "mutter": true, "gnome-shell": true,
		"xfwm4": true, "muffin": true, "marco": true,
		"hyprland": true, "sway": true, "i3": true, "bspwm": true,
		"openbox": true, "awesome": true, "dwm": true, "qtile": true,
		"herbstluftwm": true, "xmonad": true, "river": true, "niri": true,
	}
	entries, _ := os.ReadDir("/proc")
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		data, err := os.ReadFile(filepath.Join("/proc", e.Name(), "comm"))
		if err != nil {
			continue
		}
		name := strings.TrimSpace(string(data))
		if lower := strings.ToLower(name); known[lower] {
			wm = name
			if de == "" && standalone[lower] {
				de = name
			}
			break
		}
	}
	return
}

func locale() string {
	for _, k := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	if v := iniLine("/etc/locale.conf", "LANG="); v != "" {
		return v
	}
	return "unknown"
}

func cpuInfo() string {
	f, err := os.Open("/proc/cpuinfo")
	if err != nil {
		return "unknown"
	}
	defer f.Close()
	var model string
	cores := 0
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		l := sc.Text()
		if model == "" && strings.HasPrefix(l, "model name") {
			if p := strings.SplitN(l, ":", 2); len(p) == 2 {
				model = strings.NewReplacer("(R)", "", "(TM)", "", "  ", " ").
					Replace(strings.TrimSpace(p[1]))
			}
		}
		if strings.HasPrefix(l, "processor") {
			cores++
		}
	}
	if model == "" {
		return "unknown"
	}
	if data, err := os.ReadFile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"); err == nil {
		if khz, err := strconv.ParseFloat(strings.TrimSpace(string(data)), 64); err == nil {
			return fmt.Sprintf("%s (%d) @ %.2f GHz", model, cores, khz/1e6)
		}
	}
	return fmt.Sprintf("%s (%d)", model, cores)
}

func gpuList() []string {
	entries, err := os.ReadDir("/sys/class/drm")
	if err != nil {
		return lspciGPUs()
	}
	seen := map[string]bool{}
	var result, nvidiaDevs []string
	for _, e := range entries {
		n := e.Name()
		if !strings.HasPrefix(n, "card") || strings.Contains(n, "-") {
			continue
		}
		dev := filepath.Join("/sys/class/drm", n, "device")
		v, d := sysRead(dev, "vendor"), sysRead(dev, "device")
		if v == "" || d == "" || seen[v+":"+d] {
			continue
		}
		seen[v+":"+d] = true
		if v == "0x10de" {
			nvidiaDevs = append(nvidiaDevs, dev)
		} else if name := lspciName(dev); name != "" {
			result = append(result, name)
		} else {
			result = append(result, vendorName(v))
		}
	}
	if len(nvidiaDevs) > 0 {
		if names := nvidiaSMI(); len(names) > 0 {
			result = append(result, names...)
		} else {
			for range nvidiaDevs {
				result = append(result, "NVIDIA GPU")
			}
		}
	}
	if len(result) == 0 {
		return lspciGPUs()
	}
	return result
}

func nvidiaSMI() []string {
	out, err := exec.Command("nvidia-smi", "--query-gpu=name", "--format=csv,noheader,nounits").Output()
	if err != nil {
		return nil
	}
	var r []string
	for _, l := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if n := strings.TrimSpace(l); n != "" {
			r = append(r, n)
		}
	}
	return r
}

func sysRead(base, name string) string {
	data, _ := os.ReadFile(filepath.Join(base, name))
	return strings.TrimSpace(string(data))
}

func lspciName(devPath string) string {
	link, err := os.Readlink(devPath)
	if err != nil {
		return ""
	}
	out, err := exec.Command("lspci", "-mm").Output()
	if err != nil {
		return ""
	}
	addr := filepath.Base(link)
	for _, l := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(l, addr) {
			if p := strings.Split(l, `"`); len(p) >= 6 {
				return strings.TrimSpace(p[5])
			}
		}
	}
	return ""
}

func vendorName(v string) string {
	switch v {
	case "0x1002":
		return "AMD GPU"
	case "0x10de":
		return "NVIDIA GPU"
	case "0x8086":
		return "Intel GPU"
	}
	return "Unknown GPU"
}

func lspciGPUs() []string {
	out, err := exec.Command("lspci").Output()
	if err != nil {
		return []string{"unknown"}
	}
	var r []string
	for _, l := range strings.Split(string(out), "\n") {
		if strings.Contains(l, "VGA") || strings.Contains(l, "3D") || strings.Contains(l, "Display") {
			if p := strings.SplitN(l, ": ", 2); len(p) == 2 {
				r = append(r, strings.TrimSpace(p[1]))
			}
		}
	}
	if len(r) == 0 {
		return []string{"unknown"}
	}
	return r
}

func memvals() map[string]float64 {
	data, _ := os.ReadFile("/proc/meminfo")
	m := map[string]float64{}
	for _, l := range strings.Split(string(data), "\n") {
		if p := strings.Fields(l); len(p) >= 2 {
			v, _ := strconv.ParseFloat(p[1], 64)
			m[strings.TrimSuffix(p[0], ":")] = v
		}
	}
	return m
}

func memInfo() (string, string) {
	m := memvals()
	total := m["MemTotal"] / 1024
	used := total - m["MemAvailable"]/1024
	return fmt.Sprintf("%.0f MiB / %.0f MiB", used, total), progBar(used, total)
}

func swapInfo() (string, string) {
	m := memvals()
	if m["SwapTotal"] == 0 {
		return "disabled", ""
	}
	total := m["SwapTotal"] / 1024
	used := total - m["SwapFree"]/1024
	return fmt.Sprintf("%.0f MiB / %.0f MiB", used, total), progBar(used, total)
}

func diskInfo() (label, bar, fs string) {
	out, err := exec.Command("df", "-BM", "--output=source,size,used,fstype", "/").Output()
	if err != nil {
		return "unknown", "", ""
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) < 2 {
		return "unknown", "", ""
	}
	p := strings.Fields(lines[1])
	if len(p) < 4 {
		return "unknown", "", ""
	}
	parse := func(s string) float64 {
		v, _ := strconv.ParseFloat(strings.TrimRight(s, "M"), 64)
		return v
	}
	total := parse(p[1])
	used := parse(p[2])
	toGiB := func(mib float64) float64 { return mib / 1024 }
	label = fmt.Sprintf("%.1f GiB / %.1f GiB", toGiB(used), toGiB(total))
	bar = progBar(used, total)
	fs = p[3]
	return
}

func progBar(used, total float64) string {
	const w = 20
	if total == 0 {
		return ""
	}
	pct := used / total
	n := min(int(math.Round(pct*w)), w)
	return fmt.Sprintf("[%s%s] %.0f%%",
		strings.Repeat("█", n), strings.Repeat("░", w-n), pct*100)
}

func localIP() string {
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if iface.Flags&(net.FlagLoopback|net.FlagUp) != net.FlagUp {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip4 := ip.To4(); ip4 != nil && !ip4.IsLoopback() {
				return ip4.String() + " (" + iface.Name + ")"
			}
		}
	}
	return "unknown"
}

func monitors() []string {
	if m := hyprMonitors(); len(m) > 0 {
		return m
	}
	if m := xrandrMonitors(); len(m) > 0 {
		return m
	}
	return drmMonitors()
}

func hyprMonitors() []string {
	out, err := exec.Command("hyprctl", "monitors").Output()
	if err != nil {
		return nil
	}
	var result []string
	var name string
	for _, l := range strings.Split(string(out), "\n") {
		l = strings.TrimSpace(l)
		if strings.HasPrefix(l, "Monitor ") {
			name = strings.Fields(l)[1]
		}
		if name != "" && strings.Contains(l, "@") && strings.Contains(l, "at") {
			if p := strings.Fields(l); len(p) >= 1 {
				ap := strings.SplitN(p[0], "@", 2)
				hz := ""
				if len(ap) == 2 {
					hz = " @ " + strings.SplitN(ap[1], ".", 2)[0] + "Hz"
				}
				result = append(result, name+": "+ap[0]+hz)
				name = ""
			}
		}
	}
	return result
}

func xrandrMonitors() []string {
	out, err := exec.Command("xrandr").Output()
	if err != nil {
		return nil
	}
	var result []string
	for _, l := range strings.Split(string(out), "\n") {
		if strings.Contains(l, " connected") && !strings.Contains(l, "disconnected") {
			f := strings.Fields(l)
			for _, s := range f[2:] {
				if strings.Contains(s, "x") && strings.Contains(s, "+") {
					result = append(result, f[0]+": "+strings.SplitN(s, "+", 2)[0])
					break
				}
			}
		}
	}
	return result
}

func drmMonitors() []string {
	entries, err := os.ReadDir("/sys/class/drm")
	if err != nil {
		return []string{"unknown"}
	}
	var result []string
	for _, e := range entries {
		n := e.Name()
		if !strings.HasPrefix(n, "card") || !strings.Contains(n, "-") {
			continue
		}
		base := filepath.Join("/sys/class/drm", n)
		data, err := os.ReadFile(filepath.Join(base, "status"))
		if err != nil || strings.TrimSpace(string(data)) != "connected" {
			continue
		}
		label := n
		if p := strings.SplitN(n, "-", 2); len(p) == 2 {
			label = p[1]
		}
		if m, err := os.ReadFile(filepath.Join(base, "modes")); err == nil {
			if first := strings.SplitN(strings.TrimSpace(string(m)), "\n", 2)[0]; first != "" {
				result = append(result, label+": "+first)
				continue
			}
		}
		result = append(result, label)
	}
	if len(result) == 0 {
		return []string{"unknown"}
	}
	return result
}

func colorBlocks() string {
	var sb strings.Builder
	for i := range 8 {
		fmt.Fprintf(&sb, "\x1b[%dm  ", 40+i)
	}
	sb.WriteString("\x1b[0m  ")
	for i := range 8 {
		fmt.Fprintf(&sb, "\x1b[%dm  ", 100+i)
	}
	sb.WriteString("\x1b[0m")
	return sb.String()
}

func isKDE(de string) bool {
	de = strings.ToLower(de)
	return strings.Contains(de, "kde") || strings.Contains(de, "plasma")
}

func isGNOME(de string) bool {
	return strings.Contains(strings.ToLower(de), "gnome")
}

func iniGet(path, section, key string) string {
	data, _ := os.ReadFile(path)
	inSec := section == ""
	for _, l := range strings.Split(string(data), "\n") {
		l = strings.TrimSpace(l)
		if strings.HasPrefix(l, "[") {
			inSec = strings.EqualFold(l, section)
			continue
		}
		if inSec && strings.HasPrefix(l, key+"=") {
			return l[len(key)+1:]
		}
	}
	return ""
}

func kdeGet(file, section, key string) string {
	return iniGet(filepath.Join(home, ".config", file), section, key)
}

func gtkGet(file, key string) string {
	data, _ := os.ReadFile(file)
	for _, l := range strings.Split(string(data), "\n") {
		l = strings.ReplaceAll(strings.TrimSpace(l), " ", "")
		if strings.HasPrefix(l, key+"=") {
			return strings.Trim(l[len(key)+1:], `"`)
		}
	}
	return ""
}

func gsGet(schema, key string) string {
	out, err := exec.Command("gsettings", "get", schema, key).Output()
	if err != nil {
		return ""
	}
	return strings.Trim(strings.TrimSpace(string(out)), `'"`)
}

func gtkPair(key string, paths []string, de, schema, gsKey string) (a, b string) {
	for _, p := range paths[:min(2, len(paths))] {
		if v := gtkGet(p, key); v != "" {
			a = v
			break
		}
	}
	if a == "" && isGNOME(de) {
		a = gsGet(schema, gsKey)
	}
	if len(paths) > 2 {
		for _, p := range paths[2:] {
			if v := gtkGet(p, key); v != "" {
				b = v
				break
			}
		}
	}
	if b == "" && isGNOME(de) {
		b = gsGet(schema, gsKey)
	}
	return
}

func joinParts(qt, g2, g3 string) string {
	var p []string
	if qt != "" {
		p = append(p, qt+" [Qt]")
	}
	switch {
	case g2 != "" && g2 == g3:
		p = append(p, g2+" [GTK2/3]")
	default:
		if g2 != "" {
			p = append(p, g2+" [GTK2]")
		}
		if g3 != "" {
			p = append(p, g3+" [GTK3]")
		}
	}
	if len(p) == 0 {
		return "unknown"
	}
	return strings.Join(p, ", ")
}

func wmTheme(de string) string {
	if isKDE(de) {
		if v := kdeGet("kdeglobals", "[KDE]", "widgetStyle"); v != "" {
			return v
		}
		if v := kdeGet("kwinrc", "[org.kde.kdecoration2]", "theme"); v != "" {
			p := strings.Split(v, "__")
			return p[len(p)-1]
		}
	}
	if isGNOME(de) {
		if v := gsGet("org.gnome.shell.extensions.user-theme", "name"); v != "" {
			return v
		}
	}
	return "unknown"
}

var (
	gtk2rc  = home + "/.gtkrc-2.0"
	gtk2cfg = home + "/.config/gtk-2.0/gtkrc"
	gtk3cfg = home + "/.config/gtk-3.0/settings.ini"
)

func themeInfo(de string) string {
	qt := kdeGet("kdeglobals", "[General]", "ColorScheme")
	if qt == "" {
		qt = kdeGet("kdeglobals", "[General]", "widgetStyle")
	}
	g2, g3 := gtkPair("gtk-theme-name",
		[]string{gtk2rc, gtk2cfg, gtk3cfg, "/etc/gtk-3.0/settings.ini"},
		de, "org.gnome.desktop.interface", "gtk-theme")
	return joinParts(qt, g2, g3)
}

func iconsInfo(de string) string {
	qt := ""
	if isKDE(de) {
		qt = kdeGet("kdeglobals", "[Icons]", "Theme")
	}
	g2, g3 := gtkPair("gtk-icon-theme-name",
		[]string{gtk2rc, gtk2cfg, gtk3cfg},
		de, "org.gnome.desktop.interface", "icon-theme")
	return joinParts(qt, g2, g3)
}

func fmtFont(s string) string {
	p := strings.Fields(strings.TrimSpace(s))
	if len(p) > 1 {
		if _, err := strconv.Atoi(p[len(p)-1]); err == nil {
			return strings.Join(p[:len(p)-1], " ") + " (" + p[len(p)-1] + "pt)"
		}
	}
	return s
}

func fontInfo(de string) string {
	qt := ""
	if isKDE(de) {
		if raw := kdeGet("kdeglobals", "[General]", "font"); raw != "" {
			if p := strings.Split(raw, ","); len(p) >= 2 {
				qt = p[0]
				if _, err := strconv.Atoi(p[1]); err == nil {
					qt += " (" + p[1] + "pt)"
				}
			}
		}
	}
	g2, g3 := gtkPair("gtk-font-name",
		[]string{gtk2rc, gtk2cfg, gtk3cfg},
		de, "org.gnome.desktop.interface", "font-name")
	return joinParts(qt, fmtFont(g2), fmtFont(g3))
}

func cursorInfo(de string) string {
	name, size := "", ""
	if isKDE(de) {
		name = kdeGet("kcminputrc", "[Mouse]", "cursorTheme")
		size = kdeGet("kcminputrc", "[Mouse]", "cursorSize")
	}
	if name == "" {
		name = gtkGet(gtk3cfg, "gtk-cursor-theme-name")
	}
	if size == "" {
		size = gtkGet(gtk3cfg, "gtk-cursor-theme-size")
	}
	if name == "" {
		name = gtkGet(gtk2rc, "gtk-cursor-theme-name")
	}
	if name == "" && isGNOME(de) {
		name = gsGet("org.gnome.desktop.interface", "cursor-theme")
		if size == "" {
			size = gsGet("org.gnome.desktop.interface", "cursor-size")
		}
	}
	if name == "" {
		if data, err := os.ReadFile(home + "/.icons/default/index.theme"); err == nil {
			for _, l := range strings.Split(string(data), "\n") {
				if strings.HasPrefix(l, "Inherits=") {
					name = l[9:]
					break
				}
			}
		}
	}
	if name == "" {
		return "unknown"
	}
	if size != "" && size != "0" {
		return name + " (" + size + "px)"
	}
	return name
}
