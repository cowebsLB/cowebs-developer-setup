package windows

import (
	"fmt"
	"strings"
	"testing"

	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

type MockRunner struct {
	LastCommand string
	LastArgs    []string
	ReturnCode  int
	ReturnOut   string
	ReturnErr   error
}

func (m *MockRunner) Run(name string, args ...string) (int, string, error) {
	m.LastCommand = name
	m.LastArgs = args
	return m.ReturnCode, m.ReturnOut, m.ReturnErr
}

func TestWindowsAdapterBuildInstallArgs(t *testing.T) {
	adapter := NewAdapter()
	op := planner.Operation{
		ID:               "install:git",
		Kind:             "install",
		LogicalPackageID: "git",
		Manager:          "winget",
		PackageID:        "Git.Git",
		InstallOptions:   []string{"--override", "--wait"},
	}

	args, err := adapter.BuildInstallArgs(op)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expectedPrefix := []string{"install", "--id", "Git.Git", "--exact", "--source", "winget"}
	for i, exp := range expectedPrefix {
		if args[i] != exp {
			t.Errorf("arg index %d: expected %q, got %q", i, exp, args[i])
		}
	}

	joined := strings.Join(args, " ")
	if !strings.Contains(joined, "--override") || !strings.Contains(joined, "--wait") {
		t.Errorf("expected install options in args, got %v", args)
	}
}

func TestWindowsAdapterDetect(t *testing.T) {
	mock := &MockRunner{ReturnCode: 0, ReturnOut: "Git.Git Found"}
	adapter := &Adapter{WingetPath: "winget", Runner: mock}

	op := planner.Operation{
		ID:               "detect:git",
		Kind:             "detect",
		LogicalPackageID: "git",
		Manager:          "winget",
		PackageID:        "Git.Git",
	}

	installed, err := adapter.Detect(op)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !installed {
		t.Errorf("expected installed to be true when exit code is 0")
	}

	if mock.LastCommand != "winget" {
		t.Errorf("expected command winget, got %q", mock.LastCommand)
	}
}

func TestWindowsAdapterDetectNotInstalled(t *testing.T) {
	mock := &MockRunner{ReturnCode: 1, ReturnOut: "No package found", ReturnErr: fmt.Errorf("exit status 1")}
	adapter := &Adapter{WingetPath: "winget", Runner: mock}

	op := planner.Operation{
		ID:               "detect:git",
		Kind:             "detect",
		LogicalPackageID: "git",
		Manager:          "winget",
		PackageID:        "Git.Git",
	}

	installed, err := adapter.Detect(op)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if installed {
		t.Errorf("expected installed to be false when exit code is 1")
	}
}

func TestWindowsAdapterDetectReturnsProcessStartFailure(t *testing.T) {
	mock := &MockRunner{ReturnCode: -1, ReturnErr: fmt.Errorf("executable not found")}
	adapter := &Adapter{WingetPath: "winget", Runner: mock}
	_, err := adapter.Detect(planner.Operation{ID: "detect:git", LogicalPackageID: "git", Manager: "winget", PackageID: "Git.Git"})
	if err == nil || !strings.Contains(err.Error(), "failed to start Winget detection") {
		t.Fatalf("expected process start failure, got %v", err)
	}
}

func TestWindowsAdapterExecuteInstallDryRun(t *testing.T) {
	adapter := NewAdapter()
	op := planner.Operation{
		ID:               "install:git",
		Kind:             "install",
		LogicalPackageID: "git",
		Manager:          "winget",
		PackageID:        "Git.Git",
	}

	exitCode, out, err := adapter.ExecuteInstall(op, true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if exitCode != 0 {
		t.Errorf("expected exit code 0 on dry run, got %d", exitCode)
	}
	if !strings.HasPrefix(out, "PLANNED:") {
		t.Errorf("expected PLANNED prefix, got %q", out)
	}
}
