package catalog

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const validPackages = `{"schemaVersion":3,"prerequisites":[],"packages":[{"id":"git","name":"Git","tier":"core","categories":["scm"],"license":"open-source","dependencies":[],"conflicts":[],"configurationIntents":[],"providers":{"windows":[{"manager":"winget","packageId":"Git.Git","source":"winget","privilege":"elevated","scope":"auto","detection":{"type":"manager-native"},"installOptions":[],"estimate":{"downloadMbMin":1,"downloadMbMax":2,"installMinutesMin":1,"installMinutesMax":2}}]}}]}`
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

func TestLoadRequiresPrerequisiteArray(t *testing.T) {
	packages := strings.Replace(validPackages, `"prerequisites":[],`, "", 1)
	packagePath, profilePath := writeCatalogs(t, packages, validProfiles)
	if _, err := Load(packagePath, profilePath); err == nil || !strings.Contains(err.Error(), "prerequisites array is required") {
		t.Fatalf("Load() error = %v", err)
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

func TestLoadValidatesTypedRepositoryPrerequisites(t *testing.T) {
	prerequisite := `{"id":"github-cli-apt","platform":"ubuntu","type":"apt-repository","architectures":["x64"],"keyringUrl":"https://cli.github.com/packages/key.gpg","keyringSha256":"6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b","keyringPath":"/etc/apt/keyrings/github-cli.gpg","repositoryBaseUrl":"https://cli.github.com/packages","repositorySuite":"stable","repositoryComponents":["main"],"sourcesListPath":"/etc/apt/sources.list.d/github-cli.list"}`
	packages := strings.Replace(validPackages, `"prerequisites":[]`, `"prerequisites":[`+prerequisite+`]`, 1)
	packages = strings.Replace(packages, `"scope":"auto"`, `"scope":"machine","architectures":["x64"],"prerequisiteIds":["github-cli-apt"]`, 1)
	packages = strings.Replace(packages, `"windows":`, `"ubuntu":`, 1)
	packagePath, profilePath := writeCatalogs(t, packages, validProfiles)
	if _, err := Load(packagePath, profilePath); err != nil {
		t.Fatalf("valid prerequisite rejected: %v", err)
	}

	unsafe := strings.Replace(packages, `/etc/apt/keyrings/github-cli.gpg`, `/tmp/github-cli.gpg`, 1)
	packagePath, profilePath = writeCatalogs(t, unsafe, validProfiles)
	if _, err := Load(packagePath, profilePath); err == nil || !strings.Contains(err.Error(), "unsafe keyring path") {
		t.Fatalf("unsafe prerequisite error = %v", err)
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
