package configuration

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

// ErrManualConfiguration identifies configuration that deliberately remains
// interactive because it handles identity, authentication, licensing, or
// account state. Controllers may report these operations as skipped without
// treating them as installation failures.
type ErrManualConfiguration struct {
	Intent  string
	Message string
}

func (e *ErrManualConfiguration) Error() string { return e.Message }

type Command struct {
	Name string
	Args []string
}

type Runner interface {
	Run(name string, args ...string) (int, error)
}

type DefaultRunner struct{}

func (DefaultRunner) Run(name string, args ...string) (int, error) {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if cmd.ProcessState != nil {
		return cmd.ProcessState.ExitCode(), err
	}
	return -1, err
}

type LinuxHandler struct {
	HomeDir string
	Runner  Runner
}

func NewLinuxHandler() *LinuxHandler {
	home, _ := os.UserHomeDir()
	return &LinuxHandler{HomeDir: home, Runner: DefaultRunner{}}
}

func (h *LinuxHandler) Commands(op planner.Operation) ([]Command, error) {
	if op.Kind != "configure" || op.ConfigurationIntent == "" {
		return nil, fmt.Errorf("operation %s is not a typed configuration operation", op.ID)
	}
	switch op.ConfigurationIntent {
	case "git":
		return []Command{
			{Name: "git", Args: []string{"config", "--global", "init.defaultBranch", "main"}},
			{Name: "git", Args: []string{"config", "--global", "pull.rebase", "false"}},
			{Name: "git", Args: []string{"config", "--global", "core.autocrlf", "input"}},
		}, nil
	case "git-lfs":
		return []Command{{Name: "git", Args: []string{"lfs", "install"}}}, nil
	case "vscode":
		extensions := []string{
			"GitHub.copilot", "GitHub.copilot-chat", "eamodio.gitlens",
			"ms-python.python", "dbaeumer.vscode-eslint", "esbenp.prettier-vscode",
		}
		commands := make([]Command, 0, len(extensions))
		for _, extension := range extensions {
			commands = append(commands, Command{Name: "code", Args: []string{"--install-extension", extension}})
		}
		return commands, nil
	case "node":
		if h.HomeDir == "" || !filepath.IsAbs(h.HomeDir) {
			return nil, fmt.Errorf("a resolved user home is required for Node.js configuration")
		}
		return []Command{{Name: "corepack", Args: []string{"enable", "--install-directory", filepath.Join(h.HomeDir, ".local", "bin")}}}, nil
	case "github":
		return nil, &ErrManualConfiguration{Intent: "github", Message: "GitHub authentication remains an explicit manual step: run gh auth login as the target user"}
	case "aws":
		return nil, &ErrManualConfiguration{Intent: "aws", Message: "AWS authentication remains an explicit manual step: run aws configure as the target user"}
	case "azure":
		return nil, &ErrManualConfiguration{Intent: "azure", Message: "Azure authentication remains an explicit manual step: run az login as the target user"}
	case "python", "uv", "docker":
		return nil, &ErrManualConfiguration{Intent: op.ConfigurationIntent, Message: fmt.Sprintf("configuration intent %q is not supported on the current Linux provider path", op.ConfigurationIntent)}
	default:
		return nil, fmt.Errorf("unknown Linux configuration intent %q", op.ConfigurationIntent)
	}
}

func (h *LinuxHandler) Execute(op planner.Operation, dryRun bool) error {
	commands, err := h.Commands(op)
	if err != nil {
		return err
	}
	if h.Runner == nil {
		return fmt.Errorf("Linux configuration runner is required")
	}
	if op.ConfigurationIntent == "node" && !dryRun {
		if err := os.MkdirAll(filepath.Join(h.HomeDir, ".local", "bin"), 0o755); err != nil {
			return fmt.Errorf("create user executable directory: %w", err)
		}
	}
	for _, command := range commands {
		if dryRun {
			continue
		}
		exitCode, runErr := h.Runner.Run(command.Name, command.Args...)
		if runErr != nil || exitCode != 0 {
			return fmt.Errorf("configuration intent %q failed with exit code %d: %w", op.ConfigurationIntent, exitCode, runErr)
		}
	}
	return nil
}
