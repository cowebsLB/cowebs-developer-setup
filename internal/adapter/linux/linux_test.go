package linux

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

type mockRunner struct {
	lastCommand string
	lastArgs    []string
	returnCode  int
	returnOut   string
	returnErr   error
	calls       int
}

func (m *mockRunner) Run(name string, args ...string) (int, string, error) {
	m.calls++
	m.lastCommand = name
	m.lastArgs = append([]string{}, args...)
	return m.returnCode, m.returnOut, m.returnErr
}

func operation(manager, packageID string) planner.Operation {
	return planner.Operation{
		ID:               "install:test-package",
		Kind:             "install",
		LogicalPackageID: "test-package",
		Manager:          manager,
		PackageID:        packageID,
		Privilege:        "elevated",
		Scope:            "machine",
	}
}

func TestBuildInstallCommand(t *testing.T) {
	tests := []struct {
		name     string
		platform string
		op       planner.Operation
		command  string
		args     []string
	}{
		{"ubuntu apt", PlatformUbuntu, operation("apt-get", "git"), "apt-get", []string{"install", "--yes", "--no-install-recommends", "git"}},
		{"fedora dnf", PlatformFedora, operation("dnf", "git"), "dnf", []string{"-y", "install", "git"}},
		{"ubuntu snap", PlatformUbuntu, withOptions(operation("snap", "code"), "--classic"), "snap", []string{"install", "code", "--classic"}},
		{"fedora snap", PlatformFedora, operation("snap", "yq"), "snap", []string{"install", "yq"}},
		{"user flatpak", PlatformUbuntu, flatpakOperation("user", "user"), "flatpak", []string{"--user", "install", "--assumeyes", "--noninteractive", "--or-update", "flathub", "com.visualstudio.code"}},
		{"system flatpak", PlatformFedora, flatpakOperation("elevated", "machine"), "flatpak", []string{"--system", "install", "--assumeyes", "--noninteractive", "--or-update", "flathub", "com.visualstudio.code"}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			adapter, err := NewAdapter(test.platform)
			if err != nil {
				t.Fatal(err)
			}
			command, args, err := adapter.BuildInstallCommand(test.op)
			if err != nil {
				t.Fatal(err)
			}
			if command != test.command || !reflect.DeepEqual(args, test.args) {
				t.Fatalf("got %s %v, want %s %v", command, args, test.command, test.args)
			}
		})
	}
}

func TestDetectUsesNativeManagerQueries(t *testing.T) {
	tests := []struct {
		platform string
		op       planner.Operation
		command  string
		args     []string
	}{
		{PlatformUbuntu, operation("apt-get", "git"), "dpkg-query", []string{"--show", "--showformat=${Status}", "git"}},
		{PlatformFedora, operation("dnf", "git"), "dnf", []string{"list", "--installed", "git"}},
		{PlatformUbuntu, operation("snap", "code"), "snap", []string{"list", "code"}},
		{PlatformFedora, flatpakOperation("user", "user"), "flatpak", []string{"--user", "info", "com.visualstudio.code"}},
	}

	for _, test := range tests {
		adapter, err := NewAdapter(test.platform)
		if err != nil {
			t.Fatal(err)
		}
		runner := &mockRunner{returnCode: 0, returnOut: "install ok installed"}
		adapter.Runner = runner
		installed, err := adapter.Detect(test.op)
		if err != nil || !installed {
			t.Fatalf("expected installed result, got installed=%v err=%v", installed, err)
		}
		if runner.lastCommand != test.command || !reflect.DeepEqual(runner.lastArgs, test.args) {
			t.Fatalf("got %s %v, want %s %v", runner.lastCommand, runner.lastArgs, test.command, test.args)
		}
	}
}

func TestDetectDistinguishesMissingAndLaunchFailure(t *testing.T) {
	adapter, _ := NewAdapter(PlatformFedora)
	runner := &mockRunner{returnCode: 1, returnErr: errors.New("exit status 1")}
	adapter.Runner = runner
	installed, err := adapter.Detect(operation("dnf", "git"))
	if err != nil || installed {
		t.Fatalf("non-zero manager result should mean not installed, got installed=%v err=%v", installed, err)
	}

	runner.returnCode = -1
	runner.returnErr = errors.New("executable not found")
	_, err = adapter.Detect(operation("dnf", "git"))
	if err == nil || !strings.Contains(err.Error(), "failed to start dnf detection") {
		t.Fatalf("expected process start failure, got %v", err)
	}
}

func TestAptDetectionRejectsResidualConfigState(t *testing.T) {
	adapter, _ := NewAdapter(PlatformUbuntu)
	adapter.Runner = &mockRunner{returnCode: 0, returnOut: "deinstall ok config-files"}
	installed, err := adapter.Detect(operation("apt-get", "git"))
	if err != nil || installed {
		t.Fatalf("residual config state must not count as installed, got installed=%v err=%v", installed, err)
	}
}

func TestExecuteInstallDryRunDoesNotInvokeRunner(t *testing.T) {
	adapter, _ := NewAdapter(PlatformUbuntu)
	runner := &mockRunner{}
	adapter.Runner = runner
	exitCode, output, err := adapter.ExecuteInstall(operation("apt-get", "git"), true)
	if err != nil || exitCode != 0 || runner.calls != 0 {
		t.Fatalf("unexpected dry-run result: code=%d calls=%d err=%v", exitCode, runner.calls, err)
	}
	if output != "PLANNED: apt-get install --yes --no-install-recommends git" {
		t.Fatalf("unexpected dry-run output %q", output)
	}
}

func TestRejectsUnsafeOrMismatchedContracts(t *testing.T) {
	tests := []struct {
		name     string
		platform string
		op       planner.Operation
	}{
		{"unsupported platform", "debian", operation("apt-get", "git")},
		{"dnf on ubuntu", PlatformUbuntu, operation("dnf", "git")},
		{"apt on fedora", PlatformFedora, operation("apt-get", "git")},
		{"blank package", PlatformUbuntu, operation("apt-get", " ")},
		{"option-shaped package", PlatformUbuntu, operation("apt-get", "--allow-downgrades")},
		{"control character package", PlatformUbuntu, operation("apt-get", "git\n--option")},
		{"custom apt source", PlatformUbuntu, withSource(operation("apt-get", "git"), "third-party")},
		{"apt user scope", PlatformUbuntu, withPrivilege(operation("apt-get", "git"), "user", "user")},
		{"flatpak without source", PlatformUbuntu, withPrivilege(operation("flatpak", "com.visualstudio.code"), "user", "user")},
		{"option-shaped flatpak source", PlatformUbuntu, withPrivilege(withSource(operation("flatpak", "com.visualstudio.code"), "--user"), "user", "user")},
		{"flatpak invalid scope", PlatformUbuntu, withPrivilege(withSource(operation("flatpak", "com.visualstudio.code"), "flathub"), "elevated", "auto")},
		{"empty option", PlatformUbuntu, withOptions(operation("apt-get", "git"), " ")},
		{"control character option", PlatformUbuntu, withOptions(operation("apt-get", "git"), "--option\nvalue")},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			adapter, err := NewAdapter(test.platform)
			if err != nil {
				if test.name == "unsupported platform" {
					return
				}
				t.Fatal(err)
			}
			if _, _, err := adapter.BuildInstallCommand(test.op); err == nil {
				t.Fatal("expected contract rejection")
			}
		})
	}
}

func withOptions(op planner.Operation, options ...string) planner.Operation {
	op.InstallOptions = options
	return op
}

func withSource(op planner.Operation, source string) planner.Operation {
	op.Source = source
	return op
}

func withPrivilege(op planner.Operation, privilege, scope string) planner.Operation {
	op.Privilege = privilege
	op.Scope = scope
	return op
}

func flatpakOperation(privilege, scope string) planner.Operation {
	op := operation("flatpak", "com.visualstudio.code")
	op.Source = "flathub"
	op.Privilege = privilege
	op.Scope = scope
	return op
}
