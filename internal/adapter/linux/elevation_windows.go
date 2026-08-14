//go:build windows

package linux

func IsElevated() (bool, error) { return false, nil }
