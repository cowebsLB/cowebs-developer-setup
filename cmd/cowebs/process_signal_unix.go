//go:build !windows

package main

import (
	"os"
	"os/exec"
	"syscall"
	"time"
)

func prepareInterruptibleChild(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}

func interruptChild(command *exec.Cmd, interrupt os.Signal, done <-chan struct{}) {
	if command.Process == nil {
		return
	}
	processGroup := -command.Process.Pid
	_ = syscall.Kill(processGroup, interrupt.(syscall.Signal))
	timer := time.NewTimer(10 * time.Second)
	defer timer.Stop()
	select {
	case <-done:
	case <-timer.C:
		_ = syscall.Kill(processGroup, syscall.SIGKILL)
	}
}
