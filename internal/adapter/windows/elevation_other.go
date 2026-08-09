//go:build !windows

package windows

func IsElevated() (bool, error) { return false, nil }
