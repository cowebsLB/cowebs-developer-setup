//go:build windows

package main

import (
	"os"
	"os/exec"
)

func prepareInterruptibleChild(_ *exec.Cmd) {}

func interruptChild(command *exec.Cmd, interrupt os.Signal, _ <-chan struct{}) {
	if command.Process != nil {
		_ = command.Process.Signal(interrupt)
	}
}
