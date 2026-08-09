package windows

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

type Adapter struct {
	WingetPath string
	Runner     CommandRunner
}

type CommandRunner interface {
	Run(name string, args ...string) (int, string, error)
}

type DefaultRunner struct{}

func (r DefaultRunner) Run(name string, args ...string) (int, string, error) {
	cmd := exec.Command(name, args...)
	output, err := cmd.CombinedOutput()
	exitCode := -1
	if cmd.ProcessState != nil {
		exitCode = cmd.ProcessState.ExitCode()
	}
	return exitCode, string(output), err
}

func NewAdapter() *Adapter {
	return &Adapter{
		WingetPath: "winget",
		Runner:     DefaultRunner{},
	}
}

func (a *Adapter) Detect(op planner.Operation) (bool, error) {
	if op.Manager != "winget" {
		return false, fmt.Errorf("unsupported manager %q for Windows adapter", op.Manager)
	}
	if op.PackageID == "" {
		return false, fmt.Errorf("missing package ID for operation %s", op.ID)
	}
	args := []string{"list", "--id", op.PackageID, "--exact", "--accept-source-agreements", "--disable-interactivity"}
	exitCode, _, err := a.Runner.Run(a.WingetPath, args...)
	if exitCode == 0 {
		return true, nil
	}
	if exitCode < 0 {
		return false, fmt.Errorf("failed to start Winget detection for %s: %w", op.LogicalPackageID, err)
	}
	return false, nil
}

func (a *Adapter) BuildInstallArgs(op planner.Operation) ([]string, error) {
	if op.Manager != "winget" {
		return nil, fmt.Errorf("unsupported manager %q for Windows adapter", op.Manager)
	}
	if op.PackageID == "" {
		return nil, fmt.Errorf("missing package ID for operation %s", op.ID)
	}
	args := []string{
		"install",
		"--id", op.PackageID,
		"--exact",
		"--source", "winget",
		"--silent",
		"--accept-package-agreements",
		"--accept-source-agreements",
		"--disable-interactivity",
	}

	for _, opt := range op.InstallOptions {
		trimmed := strings.TrimSpace(opt)
		if trimmed != "" {
			args = append(args, trimmed)
		}
	}

	return args, nil
}

func (a *Adapter) ExecuteInstall(op planner.Operation, dryRun bool) (int, string, error) {
	args, err := a.BuildInstallArgs(op)
	if err != nil {
		return 1, "", err
	}
	if dryRun {
		return 0, fmt.Sprintf("PLANNED: %s %s", a.WingetPath, strings.Join(args, " ")), nil
	}
	return a.Runner.Run(a.WingetPath, args...)
}
