package catalog

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const validPackages = `{"schemaVersion":3,"packages":[{"id":"git","name":"Git","tier":"core","categories":["scm"],"license":"open-source","dependencies":[],"conflicts":[],"configurationIntents":[],"providers":{"windows":[{"manager":"winget","packageId":"Git.Git","source":"winget","privilege":"elevated","scope":"auto","detection":{"type":"manager-native"},"installOptions":[],"estimate":{"downloadMbMin":1,"downloadMbMax":2,"installMinutesMin":1,"installMinutesMax":2}}]}}]}`
const validProfiles = `{"schemaVersion":3,"corePackageIds":["git"],"packs":[],"profiles":[{"id":"backend","name":"Backend","extends":[],"packageIds":[],"recommendedPackIds":[],"optionalPackIds":[]}]}`

func TestLoadStrictCatalogs(t *testing.T) {
	packagePath, profilePath := writeCatalogs(t, validPackages, validProfiles)
	catalogs, err := Load(packagePath, profilePath)
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if catalogs.CatalogSHA256 == "" || catalogs.PackageByID["git"].Name != "Git" {
		t.Fatalf("Load() returned incomplete catalogs: %#v", catalogs)
	}
}

func TestLoadRejectsUnknownFieldsAndTrailingJSON(t *testing.T) {
	for name, packageJSON := range map[string]string{
		"unknown field": strings.Replace(validPackages, `"schemaVersion":3`, `"schemaVersion":3,"command":"unsafe"`, 1),
		"trailing JSON": validPackages + `{}`,
	} {
		t.Run(name, func(t *testing.T) {
			packagePath, profilePath := writeCatalogs(t, packageJSON, validProfiles)
			if _, err := Load(packagePath, profilePath); err == nil {
				t.Fatal("Load() accepted invalid JSON")
			}
		})
	}
}

func TestLoadRejectsUnknownReferences(t *testing.T) {
	profiles := strings.Replace(validProfiles, `"corePackageIds":["git"]`, `"corePackageIds":["missing"]`, 1)
	packagePath, profilePath := writeCatalogs(t, validPackages, profiles)
	_, err := Load(packagePath, profilePath)
	if err == nil || !strings.Contains(err.Error(), "unknown package") {
		t.Fatalf("Load() error = %v, want unknown package", err)
	}
}

func writeCatalogs(t *testing.T, packages, profiles string) (string, string) {
	t.Helper()
	directory := t.TempDir()
	packagePath := filepath.Join(directory, "packages.json")
	profilePath := filepath.Join(directory, "profiles.json")
	if err := os.WriteFile(packagePath, []byte(packages), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(profilePath, []byte(profiles), 0o600); err != nil {
		t.Fatal(err)
	}
	return packagePath, profilePath
}
