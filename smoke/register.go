package smoke

import (
	"github.com/dash-xd/nix-alpine/quadlet"
	"github.com/xd-dash/smoke/command"
)

func init() { command.Register("nix-alpine", quadlet.Run) }
