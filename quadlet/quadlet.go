package quadlet

import (
 "flag"
 "fmt"
 "os"
 "os/exec"
 "path/filepath"
 "strings"
)

const defaultImage = "localhost/nix-alpine:daemon"

func Run(args []string) error {
 if len(args)==0 { return fmt.Errorf("usage: nix-alpine <install|start|stop|status> [options]") }
 switch args[0] {
 case "install": return install(args[1:])
 case "start", "stop", "status": return systemctl(args[0], args[1:])
 default: return fmt.Errorf("unknown nix-alpine operation %q", args[0])
 }
}

func install(args []string) error {
 fs:=flag.NewFlagSet("nix-alpine install", flag.ContinueOnError)
 name:=fs.String("name","","logical application/scope name")
 flake:=fs.String("flake","","host directory containing the flake")
 target:=fs.String("target","#default","flake installable suffix")
 image:=fs.String("image",defaultImage,"nix-alpine OCI image")
 root:=fs.String("quadlet-dir","","override user Quadlet directory")
 if err:=fs.Parse(args); err!=nil{return err}
 if !validName(*name){return fmt.Errorf("invalid --name %q",*name)}
 abs,err:=filepath.Abs(*flake);if err!=nil{return err};st,err:=os.Stat(abs);if err!=nil{return err};if !st.IsDir(){return fmt.Errorf("flake path is not a directory: %s",abs)}
 dir:=*root;if dir==""{home,err:=os.UserHomeDir();if err!=nil{return err};dir=filepath.Join(home,".config","containers","systemd")}
 if err:=os.MkdirAll(dir,0755);err!=nil{return err}
 dst:=filepath.Join(dir,"nix-alpine-"+*name+".container");tmp:=dst+".tmp"
 if err:=os.WriteFile(tmp,[]byte(render(*name,abs,*target,*image)),0644);err!=nil{return err}
 if err:=os.Rename(tmp,dst);err!=nil{return err}
 fmt.Println(dst);return nil
}

func render(name,flake,target,image string) string {
 return fmt.Sprintf("[Unit]\nDescription=nix-alpine flake runner (%s)\nAfter=network-online.target\n\n[Container]\nImage=%s\nContainerName=nix-alpine-%s\nVolume=nix-alpine-%s-store.volume:/nix\nVolume=%s:/workspace:ro\nWorkingDir=/workspace\nExec=nix run /workspace%s\n\n[Service]\nRestart=on-failure\n\n[Install]\nWantedBy=default.target\n",name,image,name,name,flake,target)
}

func systemctl(op string,args []string) error {
 if len(args)!=1||!validName(args[0]){return fmt.Errorf("usage: nix-alpine %s NAME",op)}
 cmd:=exec.Command("systemctl","--user",op,"nix-alpine-"+args[0]+".service");cmd.Stdout=os.Stdout;cmd.Stderr=os.Stderr;return cmd.Run()
}
func validName(s string) bool {if s==""{return false};for _,r:=range s{if !(r>='a'&&r<='z'||r>='A'&&r<='Z'||r>='0'&&r<='9'||strings.ContainsRune("_.-",r)){return false}};return true}
