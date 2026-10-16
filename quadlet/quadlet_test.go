package quadlet

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInstallWritesScopedStoreAndContainer(t *testing.T) {
	root := t.TempDir()
	flake := filepath.Join(root, "flake")
	if err := os.Mkdir(flake, 0755); err != nil { t.Fatal(err) }
	out := filepath.Join(root, "quadlet")
	if err := install([]string{"--name", "api", "--flake", flake, "--target", "#server", "--quadlet-dir", out}); err != nil { t.Fatal(err) }

	volume, err := os.ReadFile(filepath.Join(out, "nix-alpine-api-store.volume"))
	if err != nil { t.Fatal(err) }
	if !strings.Contains(string(volume), "VolumeName=nix-alpine-api-store") { t.Fatalf("unexpected volume:\n%s", volume) }

	container, err := os.ReadFile(filepath.Join(out, "nix-alpine-api.container"))
	if err != nil { t.Fatal(err) }
	body := string(container)
	for _, want := range []string{
		"Volume=nix-alpine-api-store.volume:/nix",
		"Volume="+flake+":/workspace:ro",
		"Exec=nix run /workspace#server",
		"Image=localhost/nix-toolbox:latest",
	} {
		if !strings.Contains(body, want) { t.Fatalf("container missing %q:\n%s", want, body) }
	}
	if strings.Contains(body, "daemon") || strings.Contains(body, "socket") { t.Fatalf("daemon plumbing leaked into single-user unit:\n%s", body) }
}

func TestInvalidScope(t *testing.T) {
	if validName("../shared") { t.Fatal("path-like scope accepted") }
}

func TestSystemctlLifecycleTargetsGeneratedUserService(t *testing.T) {
	dir := t.TempDir()
	log := filepath.Join(dir, "args")
	script := filepath.Join(dir, "systemctl")
	body := "#!/bin/sh\nprintf '%s\\n' \"$@\" > " + log + "\n"
	if err := os.WriteFile(script, []byte(body), 0755); err != nil { t.Fatal(err) }
	t.Setenv("PATH", dir+":"+os.Getenv("PATH"))

	if err := systemctl("start", []string{"api"}); err != nil { t.Fatal(err) }
	got, err := os.ReadFile(log)
	if err != nil { t.Fatal(err) }
	if string(got) != "--user\nstart\nnix-alpine-api.service\n" {
		t.Fatalf("unexpected systemctl invocation: %q", got)
	}
}

func TestReloadTargetsUserManager(t *testing.T) {
	dir := t.TempDir()
	log := filepath.Join(dir, "args")
	script := filepath.Join(dir, "systemctl")
	body := "#!/bin/sh\nprintf '%s\\n' \"$@\" > " + log + "\n"
	if err := os.WriteFile(script, []byte(body), 0755); err != nil { t.Fatal(err) }
	t.Setenv("PATH", dir+":"+os.Getenv("PATH"))

	if err := reloadUserSystemd(); err != nil { t.Fatal(err) }
	got, err := os.ReadFile(log)
	if err != nil { t.Fatal(err) }
	if string(got) != "--user\ndaemon-reload\n" {
		t.Fatalf("unexpected systemctl reload: %q", got)
	}
}

func TestIdleWorkspaceInstall(t *testing.T) {
 root := t.TempDir()
 out := filepath.Join(root, "units")
 if err := install([]string{"--name","dev","--workspace",root,"--idle","--quadlet-dir",out}); err != nil { t.Fatal(err) }
 b, err := os.ReadFile(filepath.Join(out,"nix-alpine-dev.container"))
 if err != nil { t.Fatal(err) }
 for _, s := range []string{"Volume="+root+":/workspaces","Volume=nix-alpine-dev-store.volume:/nix","Exec=sleep infinity"} {
  if !strings.Contains(string(b),s) { t.Fatalf("missing %s: %s",s,b) }
 }
 if strings.Contains(string(b),"Exec=nix run") { t.Fatal("idle container runs flake") }
}
