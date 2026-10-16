package main
import("os"; _ "github.com/dash-xd/nix-alpine/smoke"; "github.com/xd-dash/smoke/identity"; "github.com/xd-dash/smoke/smokeapp")
func main(){identity.SetComponents("github.com/dash-xd/nix-alpine/smoke");smokeapp.Main(os.Args[1:])}
