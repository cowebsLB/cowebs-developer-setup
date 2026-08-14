package main

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/cowebsLB/cowebs-developer-setup/internal/journal"
	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

func TestStableProductAndVersionGrammar(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--version"}, &stdout, &stderr); code != 0 || !strings.Contains(stdout.String(), "cowebs ") {
		t.Fatalf("version command failed: code=%d stdout=%q stderr=%q", code, stdout.String(), stderr.String())
	}
	stdout.Reset()
	stderr.Reset()
	if code := run([]string{"plan", "unknown-product"}, &stdout, &stderr); code != 1 || !strings.Contains(stderr.String(), "dev-setup") {
		t.Fatalf("unknown product diagnostic failed: code=%d stderr=%q", code, stderr.String())
	}
}

func TestPrivilegedEventsRemainBoundToCanonicalSession(t *testing.T) {
	plan := &planner.Plan{PlanID: "12345678-1234-1234-1234-123456789abc", Operations: []planner.Operation{{ID: "install:git"}}}
	state := journal.NewState(plan, "sess-12345678")
	executionJournal := journal.New(filepath.Join(t.TempDir(), "events.jsonl"), filepath.Join(t.TempDir(), "state.json"))
	valid := `{"schemaVersion":1,"sessionId":"sess-12345678","sequence":1,"timestamp":"` + time.Now().UTC().Format(time.RFC3339) + `","type":"operation","status":"succeeded","operationId":"install:git","message":"processed"}` + "\n"
	if err := persistChildEvents([]byte(valid), executionJournal, state, plan); err != nil {
		t.Fatal(err)
	}
	unknown := `{"schemaVersion":1,"sessionId":"sess-12345678","sequence":2,"timestamp":"` + time.Now().UTC().Format(time.RFC3339) + `","type":"operation","status":"succeeded","operationId":"install:unknown","message":"processed"}` + "\n"
	if err := persistChildEvents([]byte(unknown), executionJournal, state, plan); err == nil {
		t.Fatal("expected unknown privileged operation rejection")
	}
}

func TestCompletionContracts(t *testing.T) {
	for _, shell := range []string{"bash", "zsh", "powershell"} {
		var output bytes.Buffer
		if err := runCompletion([]string{shell}, &output); err != nil || !strings.Contains(output.String(), "cowebs") {
			t.Fatalf("completion %s failed: %q %v", shell, output.String(), err)
		}
	}
}
