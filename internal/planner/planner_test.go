package planner

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/cowebsLB/cowebs-developer-setup/internal/catalog"
)

func TestBuildPreservesInheritancePackAndDependencyOrder(t *testing.T) {
	catalogs := testCatalogs()
	plan, err := Build(catalogs, Input{ProfileID: "child", Platform: "windows", Architecture: "x64"})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(plan.PackIDs, []string{"recommended"}) {
		t.Fatalf("PackIDs = %v", plan.PackIDs)
	}
	if got := installLogicalIDs(plan); !reflect.DeepEqual(got, []string{"core", "dependency", "parent", "child", "recommended-package"}) {
		t.Fatalf("install order = %v", got)
	}
	if plan.Estimate.DownloadMBMin != 5 || plan.Estimate.DownloadMBMax != 10 {
		t.Fatalf("estimate = %#v", plan.Estimate)
	}
	if plan.Operations[3].ID != "install:dependency" || !reflect.DeepEqual(plan.Operations[3].DependsOn, []string{"detect:dependency"}) {
		t.Fatalf("dependency install operation = %#v", plan.Operations[3])
	}
	parentInstall := operationByID(plan, "install:parent")
	if !reflect.DeepEqual(parentInstall.DependsOn, []string{"install:dependency", "detect:parent"}) {
		t.Fatalf("parent dependencies = %v", parentInstall.DependsOn)
	}
}

func TestValidateCanonicalRejectsModifiedOperation(t *testing.T) {
	catalogs := testCatalogs()
	plan, err := Build(catalogs, Input{Platform: "windows", Architecture: "x64", ProfileID: "child", EssentialsOnly: true})
	if err != nil {
		t.Fatalf("Build failed: %v", err)
	}
	if err := ValidateCanonical(catalogs, plan); err != nil {
		t.Fatalf("canonical plan rejected: %v", err)
	}
	plan.Operations[0].PackageID = "Attacker.Controlled"
	if err := ValidateCanonical(catalogs, plan); err == nil {
		t.Fatal("expected modified plan rejection")
	}
}

func TestBuildEssentialsAndExplicitPacks(t *testing.T) {
	catalogs := testCatalogs()
	plan, err := Build(catalogs, Input{ProfileID: "child", EssentialsOnly: true, ExplicitPackIDs: []string{"optional"}})
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(plan.PackIDs, []string{"optional"}) {
		t.Fatalf("PackIDs = %v", plan.PackIDs)
	}
	got := installLogicalIDs(plan)
	if contains(got, "recommended-package") || !contains(got, "optional-package") {
		t.Fatalf("install ids = %v", got)
	}
}

func TestBuildRejectsConflictsAndUnsupportedTargets(t *testing.T) {
	catalogs := testCatalogs()
	_, err := Build(catalogs, Input{ProfileID: "child", ExplicitPackIDs: []string{"conflict"}})
	if err == nil || !strings.Contains(err.Error(), "package conflict") {
		t.Fatalf("conflict error = %v", err)
	}
	_, err = Build(catalogs, Input{ProfileID: "child", Architecture: "mips"})
	if err == nil || !strings.Contains(err.Error(), "unsupported architecture") {
		t.Fatalf("architecture error = %v", err)
	}
}

func TestBuildReportsEveryUnsupportedPackageInPlanOrder(t *testing.T) {
	catalogs := testCatalogs()
	ubuntuProvider := catalog.Provider{Manager: "apt-get", PackageID: "core", Privilege: "elevated", Scope: "machine", Architectures: []string{"x64"}, Detection: catalog.Detection{Type: "manager-native"}}
	core := catalogs.PackageByID["core"]
	core.Providers["ubuntu"] = []catalog.Provider{ubuntuProvider}
	catalogs.PackageByID["core"] = core

	_, err := Build(catalogs, Input{ProfileID: "child", Platform: "ubuntu", Architecture: "x64"})
	var unsupported *UnsupportedPackagesError
	if !errors.As(err, &unsupported) {
		t.Fatalf("error = %v, want UnsupportedPackagesError", err)
	}
	want := []string{"dependency", "parent", "child", "recommended-package"}
	if !reflect.DeepEqual(unsupported.PackageIDs, want) {
		t.Fatalf("unsupported package ids = %v, want %v", unsupported.PackageIDs, want)
	}
	if unsupported.Error() != "unsupported packages for ubuntu/x64: dependency, parent, child, recommended-package" {
		t.Fatalf("unexpected diagnostic: %s", unsupported.Error())
	}
}

func TestBuildIsDeterministicAndConfigurationWaitsForInstalls(t *testing.T) {
	catalogs := testCatalogs()
	first, err := Build(catalogs, Input{ProfileID: "child"})
	if err != nil {
		t.Fatal(err)
	}
	second, err := Build(catalogs, Input{ProfileID: "child"})
	if err != nil {
		t.Fatal(err)
	}
	if first.PlanID != second.PlanID || !reflect.DeepEqual(first, second) {
		t.Fatal("identical inputs did not produce identical plans")
	}
	configure := operationByID(first, "configure:git")
	if len(configure.DependsOn) != len(installLogicalIDs(first)) {
		t.Fatalf("configure depends on %d operations, want %d", len(configure.DependsOn), len(installLogicalIDs(first)))
	}
}

func testCatalogs() *catalog.Catalogs {
	packages := []catalog.Package{
		testPackage("core", nil, nil, "git"),
		testPackage("dependency", nil, nil, ""),
		testPackage("parent", []string{"dependency"}, nil, ""),
		testPackage("child", nil, nil, ""),
		testPackage("recommended-package", nil, []string{"optional-package"}, ""),
		testPackage("optional-package", nil, []string{"recommended-package"}, ""),
	}
	profiles := []catalog.Profile{
		{ID: "parent", Name: "Parent", PackageIDs: []string{"parent"}},
		{ID: "child", Name: "Child", Extends: []string{"parent"}, PackageIDs: []string{"child"}, RecommendedPackIDs: []string{"recommended"}, OptionalPackIDs: []string{"optional"}},
	}
	packs := []catalog.Pack{
		{ID: "recommended", Name: "Recommended", PackageIDs: []string{"recommended-package"}},
		{ID: "optional", Name: "Optional", PackageIDs: []string{"optional-package"}},
		{ID: "conflict", Name: "Conflict", PackageIDs: []string{"optional-package"}},
	}
	result := &catalog.Catalogs{
		Packages:    catalog.PackageCatalog{SchemaVersion: 3, Packages: packages},
		Profiles:    catalog.ProfileCatalog{SchemaVersion: 3, CorePackageIDs: []string{"core"}, Packs: packs, Profiles: profiles},
		PackageByID: map[string]catalog.Package{}, PackByID: map[string]catalog.Pack{}, ProfileByID: map[string]catalog.Profile{}, CatalogSHA256: strings.Repeat("a", 64),
	}
	for _, value := range packages {
		result.PackageByID[value.ID] = value
	}
	for _, value := range packs {
		result.PackByID[value.ID] = value
	}
	for _, value := range profiles {
		result.ProfileByID[value.ID] = value
	}
	return result
}

func testPackage(id string, dependencies, conflicts []string, intent string) catalog.Package {
	intents := []string{}
	if intent != "" {
		intents = append(intents, intent)
	}
	return catalog.Package{ID: id, Dependencies: dependencies, Conflicts: conflicts, ConfigurationIntents: intents, Providers: map[string][]catalog.Provider{
		"windows": {{Manager: "winget", PackageID: "Test." + id, Source: "winget", Privilege: "elevated", Scope: "auto", Detection: catalog.Detection{Type: "manager-native"}, Estimate: catalog.Estimate{DownloadMBMin: 1, DownloadMBMax: 2, InstallMinutesMin: 1, InstallMinutesMax: 2}}},
	}}
}

func installLogicalIDs(plan *Plan) []string {
	result := []string{}
	for _, operation := range plan.Operations {
		if operation.Kind == "install" {
			result = append(result, operation.LogicalPackageID)
		}
	}
	return result
}

func operationByID(plan *Plan, id string) Operation {
	for _, operation := range plan.Operations {
		if operation.ID == id {
			return operation
		}
	}
	return Operation{}
}
