package quadlet

import (
 "os"
 "path/filepath"
 "strings"
 "testing"
)

func TestInstallRendersScopedUnit(t *testing.T) {
 d:=t.TempDir();f:=filepath.Join(d,"flake")
 if err:=os.Mkdir(f,0755);err!=nil{t.Fatal(err)}
 q:=filepath.Join(d,"quadlets")
 if err:=install([]string{"--name","app1","--flake",f,"--target","#server","--quadlet-dir",q});err!=nil{t.Fatal(err)}
 b,err:=os.ReadFile(filepath.Join(q,"nix-alpine-app1.container"));if err!=nil{t.Fatal(err)}
 s:=string(b)
 for _,want:=range []string{"nix-alpine-app1-store.volume:/nix",f+":/workspace:ro","Exec=nix run /workspace#server"}{if !strings.Contains(s,want){t.Fatalf("missing %q in %s",want,s)}}
}
func TestInvalidName(t *testing.T){if validName("../x"){t.Fatal("accepted traversal")}}
