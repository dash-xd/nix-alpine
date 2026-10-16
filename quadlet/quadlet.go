package quadlet

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const defaultImage = "localhost/nix-toolbox:latest"

func Run(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: nix-alpine <install|start|stop|status> [options]")
	}
	switch args[0] {
	case "install":
		return install(args[1:])
	case "start", "stop", "status":
		return systemctl(args[0], args[1:])
	default:
		return fmt.Errorf("unknown nix-alpine operation %q", args[0])
	}
}

func install(args []string) error {
	fs := flag.NewFlagSet("nix-alpine install", flag.ContinueOnError)
	name := fs.String("name", "", "logical application/scope")
	flake := fs.String("flake", "", "host flake directory")
	target := fs.String("target", "#default", "flake installable suffix")
	image := fs.String("image", defaultImage, "OCI image")
	root := fs.String("quadlet-dir", "", "override user Quadlet directory (disables daemon-reload)")
	if err := fs.Parse(args); err != nil { return err }
	if !validName(*name) { return fmt.Errorf("invalid --name %q", *name) }

	abs, err := filepath.Abs(*flake)
	if err != nil { return err }
	st, err := os.Stat(abs)
	if err != nil { return err }
	if !st.IsDir() { return fmt.Errorf("flake path is not a directory: %s", abs) }

	dir := *root
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil { return err }
		dir = filepath.Join(home, ".config", "containers", "systemd")
	}
	if err := os.MkdirAll(dir, 0755); err != nil { return err }

	base := "nix-alpine-" + *name
	files := map[string]string{
		filepath.Join(dir, base+"-store.volume"): renderVolume(base),
		filepath.Join(dir, base+".container"):    renderContainer(*name, abs, *target, *image),
	}
	for dst, body := range files {
		tmp := dst + ".tmp"
		if err := os.WriteFile(tmp, []byte(body), 0644); err != nil { return err }
		if err := os.Rename(tmp, dst); err != nil { return err }
		fmt.Println(dst)
	}
	if *root == "" {
		if err := reloadUserSystemd(); err != nil { return err }
	}
	return nil
}

func reloadUserSystemd() error {
	c := exec.Command("systemctl", "--user", "daemon-reload")
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	return c.Run()
}

func renderVolume(base string) string {
	return fmt.Sprintf("[Unit]\nDescription=Persistent Nix store for %s\n\n[Volume]\nVolumeName=%s-store\n", base, base)
}

func renderContainer(name, flake, target, image string) string {
	base := "nix-alpine-" + name
	return fmt.Sprintf("[Unit]\nDescription=nix-alpine single-user flake runner (%s)\nAfter=network-online.target\n\n[Container]\nImage=%s\nContainerName=%s\nVolume=%s-store.volume:/nix\nVolume=%s:/workspace:ro\nWorkingDir=/workspace\nExec=nix run /workspace%s\n\n[Service]\nRestart=on-failure\n\n[Install]\nWantedBy=default.target\n", name, image, base, base, flake, target)
}

func systemctl(op string, args []string) error {
	if len(args) != 1 || !validName(args[0]) { return fmt.Errorf("usage: nix-alpine %s NAME", op) }
	systemctlArgs := []string{"--user", op}\n\tif op == "stop" { systemctlArgs = append(systemctlArgs, "--wait") }\n\tsystemctlArgs = append(systemctlArgs, "nix-alpine-"+args[0]+".service")\n\tc := exec.Command("systemctl", systemctlArgs...)
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	return c.Run()
}

func validName(s string) bool {
	if s == "" { return false }
	for _, r := range s {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("_.-", r)) { return false }
	}
	return true
}
