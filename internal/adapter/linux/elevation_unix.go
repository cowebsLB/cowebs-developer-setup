//go:build !windows

package linux

import "os"

func IsElevated() (bool, error) { return os.Geteuid() == 0, nil }
