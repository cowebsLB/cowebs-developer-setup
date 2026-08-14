package configuration

import (
	"errors"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

type recordingRunner struct {
	commands []Command
	exitCode int
	err      error
}

func (r *recordingRunner) Run(name string, args ...string) (int, error) {
	r.commands = append(r.commands, Command{Name: name, Args: append([]string{}, args...)})
	return r.exitCode, r.err
}

func configureOperation(intent string) planner.Operation {
	return planner.Operation{ID: "configure:" + intent, Kind: "configure", ConfigurationIntent: intent, Privilege: "user"}
}

func TestLinuxCommandsAreTypedAndPlatformSpecific(t *testing.T) {
	handler := &LinuxHandler{HomeDir: t.TempDir(), Runner: &recordingRunner{}}
	commands, err := handler.Commands(configureOperation("git"))
	if err != nil {
		t.Fatal(err)
	}
	want := []Command{
		{Name: "git", Args: []string{"config", "--global", "init.defaultBranch", "main"}},
		{Name: "git", Args: []string{"config", "--global", "pull.rebase", "false"}},
		{Name: "git", Args: []string{"config", "--global", "core.autocrlf", "input"}},
	}
	if !reflect.DeepEqual(commands, want) {
		t.Fatalf("unexpected Git commands: %#v", commands)
	}

	node, err := handler.Commands(configureOperation("node"))
	if err != nil {
		t.Fatal(err)
	}
	wantNode := filepath.Join(handler.HomeDir, ".local", "bin")
	if len(node) != 1 || node[0].Name != "corepack" || node[0].Args[len(node[0].Args)-1] != wantNode {
		t.Fatalf("unexpected Node.js command: %#v", node)
	}
}

func TestLinuxAuthenticationIntentsRemainManual(t *testing.T) {
	handler := NewLinuxHandler()
	for _, intent := range []string{"github", "aws", "azure"} {
		_, err := handler.Commands(configureOperation(intent))
		var manual *ErrManualConfiguration
		if !errors.As(err, &manual) || manual.Intent != intent {
			t.Fatalf("intent %q should be explicitly manual, got %v", intent, err)
		}
	}
}

func TestLinuxDryRunDoesNotInvokeCommands(t *testing.T) {
	runner := &recordingRunner{}
	handler := &LinuxHandler{HomeDir: t.TempDir(), Runner: runner}
	if err := handler.Execute(configureOperation("vscode"), true); err != nil {
		t.Fatal(err)
	}
	if len(runner.commands) != 0 {
		t.Fatalf("dry run invoked commands: %#v", runner.commands)
	}
}

func TestLinuxExecutionStopsOnFailure(t *testing.T) {
	runner := &recordingRunner{exitCode: 7, err: errors.New("failed")}
	handler := &LinuxHandler{HomeDir: t.TempDir(), Runner: runner}
	if err := handler.Execute(configureOperation("git-lfs"), false); err == nil {
		t.Fatal("expected configuration failure")
	}
}
