package journal

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/cowebsLB/cowebs-developer-setup/internal/broker"
	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

func TestJournalAppendReadAndState(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "journal-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	jPath := filepath.Join(tempDir, "session.jsonl")
	sPath := filepath.Join(tempDir, "state.json")

	j := New(jPath, sPath)

	events := []broker.Event{
		{
			SessionID:        "sess-123",
			Type:             "operation",
			Status:           "started",
			OperationID:      "install:git",
			LogicalPackageID: "git",
			Message:          "detecting git",
		},
		{
			SessionID:        "sess-123",
			Type:             "operation",
			Status:           "succeeded",
			OperationID:      "install:git",
			LogicalPackageID: "git",
			Message:          "git installed",
		},
		{
			SessionID:        "sess-123",
			Type:             "operation",
			Status:           "failed",
			OperationID:      "install:node",
			LogicalPackageID: "node",
			Message:          "node failed",
		},
	}

	for _, ev := range events {
		if err := j.AppendEvent(ev); err != nil {
			t.Fatalf("failed to append event: %v", err)
		}
	}

	readEvs, err := j.ReadEvents()
	if err != nil {
		t.Fatalf("failed to read events: %v", err)
	}
	if len(readEvs) != 3 {
		t.Fatalf("expected 3 events, got %d", len(readEvs))
	}

	state := BuildStateFromEvents(readEvs)
	if state.SessionID != "sess-123" {
		t.Errorf("expected sessionId sess-123, got %q", state.SessionID)
	}
	if len(state.CompletedOperations) != 1 || state.CompletedOperations[0] != "install:git" {
		t.Errorf("expected completed ops [install:git], got %v", state.CompletedOperations)
	}
	if len(state.FailedOperations) != 1 || state.FailedOperations[0] != "install:node" {
		t.Errorf("expected failed ops [install:node], got %v", state.FailedOperations)
	}

	if err := j.SaveState(state); err != nil {
		t.Fatalf("failed to save state: %v", err)
	}

	loadedState, err := j.LoadState()
	if err != nil {
		t.Fatalf("failed to load state: %v", err)
	}
	if loadedState.SessionID != "sess-123" {
		t.Errorf("expected loaded state sessionId sess-123, got %q", loadedState.SessionID)
	}

	loadedState.LastSequence = 3
	if err := j.SaveState(loadedState); err != nil {
		t.Fatalf("failed to atomically replace existing state: %v", err)
	}

	reopened := New(jPath, sPath)
	if err := reopened.AppendEvent(broker.Event{SessionID: "sess-123", Sequence: 4, Type: "operation", Status: "skipped", OperationID: "install:node", Message: "already installed"}); err != nil {
		t.Fatalf("failed to continue journal sequence: %v", err)
	}
	if err := reopened.AppendEvent(broker.Event{SessionID: "sess-123", Sequence: 4, Type: "operation", Status: "skipped", OperationID: "install:node", Message: "duplicate"}); err == nil {
		t.Fatal("expected duplicate journal sequence rejection")
	}
}

func TestValidateForPlanRejectsMismatchedResumeState(t *testing.T) {
	plan := &planner.Plan{PlanID: "12345678-1234-1234-1234-123456789abc", CatalogSHA256: "hash", Platform: "windows", Architecture: "x64", ProfileID: "backend", Operations: []planner.Operation{{ID: "detect:git"}}}
	state := NewState(plan, "sess-123")
	state.CatalogSHA256 = "tampered"
	if err := ValidateForPlan(state, plan); err == nil {
		t.Fatal("expected mismatched state rejection")
	}
}
