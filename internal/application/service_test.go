package application

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

func TestPlanPersistenceRejectsTrailingJSON(t *testing.T) {
	path := filepath.Join(t.TempDir(), "plan.json")
	plan := &planner.Plan{SchemaVersion: 1, PlanID: "12345678-1234-1234-1234-123456789abc"}
	if err := SavePlan(path, plan); err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadPlan(path)
	if err != nil || loaded.PlanID != plan.PlanID {
		t.Fatalf("load plan: %#v %v", loaded, err)
	}
	if err := os.WriteFile(path, []byte("{}{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadPlan(path); err == nil {
		t.Fatal("expected trailing JSON rejection")
	}
}
