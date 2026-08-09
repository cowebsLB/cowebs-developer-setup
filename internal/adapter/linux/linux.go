package linux

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

const (
	PlatformUbuntu = "ubuntu"
	PlatformFedora = "fedora"
)

type Adapter struct {
	Platform string
	Paths    map[string]string
	Runner   CommandRunner
}

type CommandRunner interface {
	Run(name string, args ...string) (int, string, error)
}

type DefaultRunner struct{}

func (DefaultRunner) Run(name string, args ...string) (int, string, error) {
	cmd := exec.Command(name, args...)
	output, err := cmd.CombinedOutput()
	exitCode := -1
	if cmd.ProcessState != nil {
		exitCode = cmd.ProcessState.ExitCode()
	}
	return exitCode, string(output), err
}

func NewAdapter(platform string) (*Adapter, error) {
	if platform != PlatformUbuntu && platform != PlatformFedora {
		return nil, fmt.Errorf("unsupported Linux platform %q", platform)
	}
	return &Adapter{
		Platform: platform,
		Paths: map[string]string{
			"apt-get":    "apt-get",
			"dpkg-query": "dpkg-query",
			"dnf":        "dnf",
			"snap":       "snap",
			"flatpak":    "flatpak",
		},
		Runner: DefaultRunner{},
	}, nil
}

func (a *Adapter) Detect(op planner.Operation) (bool, error) {
	if err := a.validateOperation(op); err != nil {
		return false, err
	}

	command, args, err := a.detectionCommand(op)
	if err != nil {
		return false, err
	}
	exitCode, output, err := a.Runner.Run(command, args...)
	if exitCode == 0 {
		if op.Manager == "apt-get" && strings.TrimSpace(output) != "install ok installed" {
			return false, nil
		}
		return true, nil
	}
	if exitCode < 0 {
		return false, fmt.Errorf("failed to start %s detection for %s: %w", op.Manager, op.LogicalPackageID, err)
	}
	return false, nil
}

func (a *Adapter) BuildInstallCommand(op planner.Operation) (string, []string, error) {
	if err := a.validateOperation(op); err != nil {
		return "", nil, err
	}

	options := make([]string, 0, len(op.InstallOptions))
	for _, option := range op.InstallOptions {
		trimmed := strings.TrimSpace(option)
		if trimmed == "" {
			return "", nil, fmt.Errorf("empty install option for operation %s", op.ID)
		}
		if trimmed != option || strings.ContainsAny(option, "\r\n\x00") {
			return "", nil, fmt.Errorf("invalid install option for operation %s", op.ID)
		}
		options = append(options, trimmed)
	}

	switch op.Manager {
	case "apt-get":
		args := []string{"install", "--yes", "--no-install-recommends"}
		args = append(args, options...)
		return a.path("apt-get"), append(args, op.PackageID), nil
	case "dnf":
		args := []string{"-y", "install"}
		args = append(args, options...)
		return a.path("dnf"), append(args, op.PackageID), nil
	case "snap":
		args := []string{"install", op.PackageID}
		return a.path("snap"), append(args, options...), nil
	case "flatpak":
		args := []string{scopeArgument(op.Scope), "install", "--assumeyes", "--noninteractive", "--or-update"}
		args = append(args, options...)
		args = append(args, op.Source, op.PackageID)
		return a.path("flatpak"), args, nil
	default:
		return "", nil, fmt.Errorf("unsupported manager %q for Linux adapter", op.Manager)
	}
}

func (a *Adapter) ExecuteInstall(op planner.Operation, dryRun bool) (int, string, error) {
	command, args, err := a.BuildInstallCommand(op)
	if err != nil {
		return 1, "", err
	}
	if dryRun {
		return 0, fmt.Sprintf("PLANNED: %s %s", command, strings.Join(args, " ")), nil
	}
	return a.Runner.Run(command, args...)
}

func (a *Adapter) detectionCommand(op planner.Operation) (string, []string, error) {
	switch op.Manager {
	case "apt-get":
		return a.path("dpkg-query"), []string{"--show", "--showformat=${Status}", op.PackageID}, nil
	case "dnf":
		return a.path("dnf"), []string{"list", "--installed", op.PackageID}, nil
	case "snap":
		return a.path("snap"), []string{"list", op.PackageID}, nil
	case "flatpak":
		return a.path("flatpak"), []string{scopeArgument(op.Scope), "info", op.PackageID}, nil
	default:
		return "", nil, fmt.Errorf("unsupported manager %q for Linux detection", op.Manager)
	}
}

func (a *Adapter) validateOperation(op planner.Operation) error {
	if a == nil {
		return fmt.Errorf("Linux adapter is required")
	}
	if a.Runner == nil {
		return fmt.Errorf("Linux command runner is required")
	}
	if a.Platform != PlatformUbuntu && a.Platform != PlatformFedora {
		return fmt.Errorf("unsupported Linux platform %q", a.Platform)
	}
	if strings.TrimSpace(op.PackageID) == "" {
		return fmt.Errorf("missing package ID for operation %s", op.ID)
	}
	if err := validatePositionalToken("package ID", op.ID, op.PackageID); err != nil {
		return err
	}

	allowed := map[string]bool{"snap": true, "flatpak": true}
	if a.Platform == PlatformUbuntu {
		allowed["apt-get"] = true
	} else {
		allowed["dnf"] = true
	}
	if !allowed[op.Manager] {
		return fmt.Errorf("manager %q is not supported on %s", op.Manager, a.Platform)
	}

	if op.Manager == "flatpak" {
		if strings.TrimSpace(op.Source) == "" {
			return fmt.Errorf("flatpak operation %s requires an explicit remote source", op.ID)
		}
		if err := validatePositionalToken("flatpak remote source", op.ID, op.Source); err != nil {
			return err
		}
		if op.Scope == "user" && op.Privilege == "user" {
			return nil
		}
		if op.Scope == "machine" && op.Privilege == "elevated" {
			return nil
		}
		return fmt.Errorf("flatpak operation %s has invalid privilege/scope %q/%q", op.ID, op.Privilege, op.Scope)
	}

	if op.Source != "" {
		return fmt.Errorf("manager %q operation %s cannot select a custom source", op.Manager, op.ID)
	}
	if op.Privilege != "elevated" || op.Scope != "machine" {
		return fmt.Errorf("manager %q operation %s requires elevated/machine privilege and scope", op.Manager, op.ID)
	}
	return nil
}

func (a *Adapter) path(manager string) string {
	if path := a.Paths[manager]; path != "" {
		return path
	}
	return manager
}

func scopeArgument(scope string) string {
	if scope == "user" {
		return "--user"
	}
	return "--system"
}

func validatePositionalToken(name, operationID, value string) error {
	if strings.TrimSpace(value) != value {
		return fmt.Errorf("%s for operation %s contains surrounding whitespace", name, operationID)
	}
	if strings.HasPrefix(value, "-") {
		return fmt.Errorf("%s for operation %s cannot be parsed as an option", name, operationID)
	}
	if strings.ContainsAny(value, "\r\n\x00") {
		return fmt.Errorf("%s for operation %s contains a control character", name, operationID)
	}
	return nil
}
