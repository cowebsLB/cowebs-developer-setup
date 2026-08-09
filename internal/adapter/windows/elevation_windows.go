//go:build windows

package windows

import (
	"fmt"
	"syscall"
	"unsafe"
)

var (
	advapi32             = syscall.NewLazyDLL("advapi32.dll")
	createWellKnownSID   = advapi32.NewProc("CreateWellKnownSid")
	checkTokenMembership = advapi32.NewProc("CheckTokenMembership")
)

const winBuiltinAdministratorsSID = 26

// IsElevated reports whether the current process token is a member of the
// built-in Administrators group. It uses fixed Win32 APIs and no shell.
func IsElevated() (bool, error) {
	var size uint32
	_, _, _ = createWellKnownSID.Call(winBuiltinAdministratorsSID, 0, 0, uintptr(unsafe.Pointer(&size)))
	if size == 0 {
		return false, fmt.Errorf("could not determine Administrators SID size")
	}
	sid := make([]byte, size)
	created, _, createErr := createWellKnownSID.Call(
		winBuiltinAdministratorsSID, 0, uintptr(unsafe.Pointer(&sid[0])), uintptr(unsafe.Pointer(&size)),
	)
	if created == 0 {
		return false, fmt.Errorf("could not create Administrators SID: %w", createErr)
	}
	var member int32
	checked, _, checkErr := checkTokenMembership.Call(0, uintptr(unsafe.Pointer(&sid[0])), uintptr(unsafe.Pointer(&member)))
	if checked == 0 {
		return false, fmt.Errorf("could not inspect process token: %w", checkErr)
	}
	return member != 0, nil
}
