package broker

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"

	linuxadapter "github.com/cowebsLB/cowebs-developer-setup/internal/adapter/linux"
	"github.com/cowebsLB/cowebs-developer-setup/internal/adapter/windows"
	"github.com/cowebsLB/cowebs-developer-setup/internal/catalog"
	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

func createTestCatalog() *catalog.Catalogs {
	return &catalog.Catalogs{
		CatalogSHA256: "1111111111111111111111111111111111111111111111111111111111111111",
		Profiles:      catalog.ProfileCatalog{SchemaVersion: 3, CorePackageIDs: []string{"git"}, Profiles: []catalog.Profile{{ID: "backend", Name: "Backend"}}},
		ProfileByID:   map[string]catalog.Profile{"backend": {ID: "backend", Name: "Backend"}},
		PackByID:      map[string]catalog.Pack{},
		PackageByID: map[string]catalog.Package{
			"git": {
				ID:          "git",
				Name:        "Git",
				Description: "Distributed version control system",
				Tier:        "core",
				Categories:  []string{"source-control"},
				License:     "open-source",
				Providers: map[string][]catalog.Provider{
					"windows": {
						{
							Manager:        "winget",
							PackageID:      "Git.Git",
							Privilege:      "elevated",
							Scope:          "auto",
							InstallOptions: []string{"--override", "--wait"},
						},
					},
				},
			},
		},
	}
}

func createTestPlan(t *testing.T, catalogs *catalog.Catalogs) *planner.Plan {
	t.Helper()
	plan, err := planner.Build(catalogs, planner.Input{Platform: "windows", Architecture: "x64", ProfileID: "backend", EssentialsOnly: true})
	if err != nil {
		t.Fatalf("failed to create canonical test plan: %v", err)
	}
	return plan
}

type brokerRunner struct {
	code   int
	output string
	err    error
}

func (r brokerRunner) Run(string, ...string) (int, string, error) { return r.code, r.output, r.err }

func TestBrokerCatalogDigestMismatch(t *testing.T) {
	catalogs := createTestCatalog()
	b := NewBroker(nil)

	plan := createTestPlan(t, catalogs)
	plan.CatalogSHA256 = "2222222222222222222222222222222222222222222222222222222222222222"

	err := b.Execute(ExecutionRequest{
		Plan:     plan,
		Catalogs: catalogs,
	})

	if err == nil || !strings.Contains(err.Error(), "catalog digest mismatch") {
		t.Fatalf("expected catalog digest mismatch error, got: %v", err)
	}
}

func TestBrokerRejectConfigureInElevated(t *testing.T) {
	catalogs := createTestCatalog()
	b := NewBroker(nil)

	plan := createTestPlan(t, catalogs)
	plan.Operations = append(plan.Operations, planner.Operation{
		ID:                  "configure:git",
		Kind:                "configure",
		LogicalPackageID:    "git",
		ConfigurationIntent: "git",
		Privilege:           "elevated",
	})

	err := b.Execute(ExecutionRequest{
		Plan:     plan,
		Catalogs: catalogs,
	})

	if err == nil || !strings.Contains(err.Error(), "not the canonical plan") {
		t.Fatalf("expected non-canonical plan security violation, got: %v", err)
	}
}

func TestBrokerRejectUnlistedInstallOptions(t *testing.T) {
	catalogs := createTestCatalog()
	b := NewBroker(nil)

	plan := createTestPlan(t, catalogs)
	plan.Operations[1].InstallOptions = []string{"--malicious-option"}

	err := b.Execute(ExecutionRequest{
		Plan:     plan,
		Catalogs: catalogs,
	})

	if err == nil || !strings.Contains(err.Error(), "not the canonical plan") {
		t.Fatalf("expected non-canonical option security violation, got: %v", err)
	}
}

func TestBrokerValidDryRunAndEventEmissions(t *testing.T) {
	catalogs := createTestCatalog()
	mockWin := &windows.Adapter{
		WingetPath: "winget",
		Runner:     brokerRunner{code: 1, output: "No installed package found", err: fmt.Errorf("exit status 1")},
	}
	b := NewBroker(mockWin)

	plan := createTestPlan(t, catalogs)

	var outBuf bytes.Buffer
	err := b.Execute(ExecutionRequest{
		Plan:      plan,
		Catalogs:  catalogs,
		DryRun:    true,
		OutStream: &outBuf,
	})

	if err != nil {
		t.Fatalf("unexpected error during valid broker dry run: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(outBuf.String()), "\n")
	if len(lines) != 4 {
		t.Fatalf("expected 4 detect/install events, got %d lines", len(lines))
	}

	var startEv, succEv Event
	if err := json.Unmarshal([]byte(lines[2]), &startEv); err != nil {
		t.Fatalf("failed to parse event 0: %v", err)
	}
	if err := json.Unmarshal([]byte(lines[3]), &succEv); err != nil {
		t.Fatalf("failed to parse event 1: %v", err)
	}

	if startEv.Status != "started" || startEv.OperationID != "install:git" {
		t.Errorf("unexpected start event: %+v", startEv)
	}
	if succEv.Status != "planned" || succEv.OperationID != "install:git" {
		t.Errorf("unexpected success event: %+v", succEv)
	}
}

func TestBrokerSkipsInstallWhenDetectionFindsPackage(t *testing.T) {
	catalogs := createTestCatalog()
	adapter := &windows.Adapter{WingetPath: "winget", Runner: brokerRunner{code: 0, output: "Git.Git"}}
	var out bytes.Buffer
	err := NewBroker(adapter).Execute(ExecutionRequest{Plan: createTestPlan(t, catalogs), Catalogs: catalogs, DryRun: true, OutStream: &out})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.Contains(out.String(), `"operationId":"install:git"`) || !strings.Contains(out.String(), `"status":"skipped"`) {
		t.Fatalf("expected installed package to skip install, got %s", out.String())
	}
}

func TestBrokerRejectsShortMalformedPlanWithoutPanic(t *testing.T) {
	err := NewBroker(nil).Execute(ExecutionRequest{Plan: &planner.Plan{SchemaVersion: 1, PlanID: "x"}, Catalogs: createTestCatalog()})
	if err == nil {
		t.Fatal("expected malformed plan rejection")
	}
}

func TestLinuxBrokerPartitionsMachineAndUserOperations(t *testing.T) {
	catalogs := &catalog.Catalogs{
		CatalogSHA256: "3333333333333333333333333333333333333333333333333333333333333333",
		Profiles:      catalog.ProfileCatalog{SchemaVersion: 3, CorePackageIDs: []string{"git"}, Profiles: []catalog.Profile{{ID: "backend", Name: "Backend"}}},
		ProfileByID:   map[string]catalog.Profile{"backend": {ID: "backend", Name: "Backend"}},
		PackByID:      map[string]catalog.Pack{},
		PackageByID: map[string]catalog.Package{"git": {
			ID: "git", Name: "Git", Description: "Git", Tier: "core", Categories: []string{"source-control"}, License: "open-source",
			ConfigurationIntents: []string{"git"},
			Providers:            map[string][]catalog.Provider{"fedora": {{Manager: "dnf", PackageID: "git", Privilege: "elevated", Scope: "machine", Architectures: []string{"x64"}, Detection: catalog.Detection{Type: "manager-native"}, InstallOptions: []string{}}}},
		}},
	}
	plan, err := planner.Build(catalogs, planner.Input{Platform: "fedora", Architecture: "x64", ProfileID: "backend", EssentialsOnly: true})
	if err != nil {
		t.Fatal(err)
	}
	adapter, _ := linuxadapter.NewAdapter(linuxadapter.PlatformFedora)
	adapter.Runner = brokerRunner{code: 1, err: errors.New("not installed")}
	executor := NewLinuxBroker(adapter, nil)
	var machine bytes.Buffer
	if err := executor.Execute(ExecutionRequest{Plan: plan, Catalogs: catalogs, Privilege: "elevated", DryRun: true, OutStream: &machine}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(machine.String(), `"operationId":"install:git"`) || strings.Contains(machine.String(), `"operationId":"configure:git"`) {
		t.Fatalf("machine partition leaked operations: %s", machine.String())
	}
	var user bytes.Buffer
	if err := executor.Execute(ExecutionRequest{Plan: plan, Catalogs: catalogs, Privilege: "user", DryRun: true, OutStream: &user}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(user.String(), `"operationId":"configure:git"`) || strings.Contains(user.String(), `"operationId":"install:git"`) {
		t.Fatalf("user partition leaked operations: %s", user.String())
	}
}
