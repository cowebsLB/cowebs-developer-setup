package planner

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/cowebsLB/cowebs-developer-setup/internal/catalog"
)

type Input struct {
	Platform        string
	Architecture    string
	ProfileID       string
	ExplicitPackIDs []string
	EssentialsOnly  bool
}

// ValidateCanonical verifies that a plan is exactly reproducible from the
// verified catalogs. The execution-plan v1 contract does not record whether
// recommended packs were selected implicitly, so both valid planner modes are
// reconstructed from the plan's final pack list.
func ValidateCanonical(c *catalog.Catalogs, plan *Plan) error {
	if c == nil {
		return fmt.Errorf("catalogs are required")
	}
	if plan == nil {
		return fmt.Errorf("execution plan is required")
	}
	if plan.SchemaVersion != 1 {
		return fmt.Errorf("execution plan schema version 1 is required")
	}
	if plan.CatalogSHA256 != c.CatalogSHA256 {
		return fmt.Errorf("catalog digest mismatch (plan expected %s, loaded catalog is %s)", plan.CatalogSHA256, c.CatalogSHA256)
	}

	for _, essentialsOnly := range []bool{false, true} {
		candidate, err := Build(c, Input{
			Platform:        plan.Platform,
			Architecture:    plan.Architecture,
			ProfileID:       plan.ProfileID,
			ExplicitPackIDs: append([]string{}, plan.PackIDs...),
			EssentialsOnly:  essentialsOnly,
		})
		if err == nil {
			candidateJSON, candidateErr := json.Marshal(candidate)
			planJSON, planErr := json.Marshal(plan)
			if candidateErr == nil && planErr == nil && bytes.Equal(candidateJSON, planJSON) {
				return nil
			}
		}
	}

	return fmt.Errorf("execution plan is not the canonical plan produced by the verified catalogs")
}

type Plan struct {
	SchemaVersion int              `json:"schemaVersion"`
	PlanID        string           `json:"planId"`
	CatalogSHA256 string           `json:"catalogSha256"`
	Platform      string           `json:"platform"`
	Architecture  string           `json:"architecture"`
	ProfileID     string           `json:"profileId"`
	PackIDs       []string         `json:"packIds"`
	Estimate      catalog.Estimate `json:"estimate"`
	Operations    []Operation      `json:"operations"`
}

type Operation struct {
	ID                  string   `json:"id"`
	Kind                string   `json:"kind"`
	LogicalPackageID    string   `json:"logicalPackageId"`
	Manager             string   `json:"manager,omitempty"`
	PackageID           string   `json:"packageId,omitempty"`
	Source              string   `json:"source,omitempty"`
	Privilege           string   `json:"privilege"`
	Scope               string   `json:"scope,omitempty"`
	InstallOptions      []string `json:"installOptions,omitempty"`
	ConfigurationIntent string   `json:"configurationIntent,omitempty"`
	DependsOn           []string `json:"dependsOn"`
}

type metadata struct {
	packages    []string
	recommended []string
	optional    []string
}

func Build(c *catalog.Catalogs, input Input) (*Plan, error) {
	if input.Platform == "" {
		input.Platform = "windows"
	}
	if input.Architecture == "" {
		input.Architecture = "x64"
	}
	if !contains([]string{"windows", "macos", "ubuntu", "fedora"}, input.Platform) {
		return nil, fmt.Errorf("unsupported platform %q", input.Platform)
	}
	if !contains([]string{"x86", "x64", "arm64"}, input.Architecture) {
		return nil, fmt.Errorf("unsupported architecture %q", input.Architecture)
	}
	if _, exists := c.ProfileByID[input.ProfileID]; !exists {
		return nil, fmt.Errorf("unknown profile %q", input.ProfileID)
	}

	meta, err := resolveProfile(c, input.ProfileID)
	if err != nil {
		return nil, err
	}
	selectedPacks := make([]string, 0, len(meta.recommended)+len(input.ExplicitPackIDs))
	seenPacks := map[string]bool{}
	if !input.EssentialsOnly {
		for _, id := range meta.recommended {
			appendUnique(&selectedPacks, seenPacks, id)
		}
	}
	for _, id := range input.ExplicitPackIDs {
		if _, exists := c.PackByID[id]; !exists {
			return nil, fmt.Errorf("unknown pack %q", id)
		}
		appendUnique(&selectedPacks, seenPacks, id)
	}

	packageIDs := []string{}
	seenPackages := map[string]bool{}
	var addPackage func(string, []string) error
	addPackage = func(id string, stack []string) error {
		if contains(stack, id) {
			return fmt.Errorf("package dependency cycle: %s -> %s", strings.Join(stack, " -> "), id)
		}
		pkg, exists := c.PackageByID[id]
		if !exists {
			return fmt.Errorf("unknown package %q", id)
		}
		for _, dependency := range pkg.Dependencies {
			if err := addPackage(dependency, append(append([]string{}, stack...), id)); err != nil {
				return err
			}
		}
		appendUnique(&packageIDs, seenPackages, id)
		return nil
	}
	for _, id := range c.Profiles.CorePackageIDs {
		if err := addPackage(id, nil); err != nil {
			return nil, err
		}
	}
	for _, id := range meta.packages {
		if err := addPackage(id, nil); err != nil {
			return nil, err
		}
	}
	for _, packID := range selectedPacks {
		for _, id := range c.PackByID[packID].PackageIDs {
			if err := addPackage(id, nil); err != nil {
				return nil, err
			}
		}
	}

	for _, id := range packageIDs {
		for _, conflict := range c.PackageByID[id].Conflicts {
			if seenPackages[conflict] {
				return nil, fmt.Errorf("package conflict: %q cannot be installed with %q; choose compatible packs", id, conflict)
			}
		}
	}

	providers := make(map[string]catalog.Provider, len(packageIDs))
	estimate := catalog.Estimate{}
	for _, id := range packageIDs {
		provider, err := selectProvider(c.PackageByID[id], input.Platform, input.Architecture)
		if err != nil {
			return nil, err
		}
		providers[id] = provider
		estimate.DownloadMBMin += provider.Estimate.DownloadMBMin
		estimate.DownloadMBMax += provider.Estimate.DownloadMBMax
		estimate.InstallMinutesMin += provider.Estimate.InstallMinutesMin
		estimate.InstallMinutesMax += provider.Estimate.InstallMinutesMax
	}

	operations := make([]Operation, 0, len(packageIDs)*2)
	installIDs := make([]string, 0, len(packageIDs))
	for _, id := range packageIDs {
		provider := providers[id]
		dependencyInstalls := make([]string, 0, len(c.PackageByID[id].Dependencies))
		for _, dependency := range c.PackageByID[id].Dependencies {
			dependencyInstalls = append(dependencyInstalls, "install:"+dependency)
		}
		detectID := "detect:" + id
		installID := "install:" + id
		operations = append(operations, Operation{
			ID: detectID, Kind: "detect", LogicalPackageID: id,
			Manager: provider.Manager, PackageID: provider.PackageID, Source: provider.Source,
			Privilege: provider.Privilege, Scope: provider.Scope, DependsOn: dependencyInstalls,
		})
		installDependsOn := append(append([]string{}, dependencyInstalls...), detectID)
		operations = append(operations, Operation{
			ID: installID, Kind: "install", LogicalPackageID: id,
			Manager: provider.Manager, PackageID: provider.PackageID, Source: provider.Source,
			Privilege: provider.Privilege, Scope: provider.Scope,
			InstallOptions: append([]string{}, provider.InstallOptions...), DependsOn: installDependsOn,
		})
		installIDs = append(installIDs, installID)
	}
	seenIntents := map[string]bool{}
	for _, id := range packageIDs {
		for _, intent := range c.PackageByID[id].ConfigurationIntents {
			if seenIntents[intent] {
				continue
			}
			seenIntents[intent] = true
			operations = append(operations, Operation{
				ID: "configure:" + intent, Kind: "configure", LogicalPackageID: id,
				ConfigurationIntent: intent, Privilege: "user",
				DependsOn: append([]string{}, installIDs...),
			})
		}
	}

	plan := &Plan{
		SchemaVersion: 1, CatalogSHA256: c.CatalogSHA256,
		Platform: input.Platform, Architecture: input.Architecture,
		ProfileID: input.ProfileID, PackIDs: selectedPacks,
		Estimate: estimate, Operations: operations,
	}
	plan.PlanID = deterministicPlanID(c.CatalogSHA256, input, selectedPacks)
	return plan, nil
}

func resolveProfile(c *catalog.Catalogs, id string) (metadata, error) {
	result := metadata{}
	seenPackages, seenRecommended, seenOptional := map[string]bool{}, map[string]bool{}, map[string]bool{}
	var add func(string, []string) error
	add = func(current string, stack []string) error {
		if contains(stack, current) {
			return fmt.Errorf("profile inheritance cycle: %s -> %s", strings.Join(stack, " -> "), current)
		}
		profile, exists := c.ProfileByID[current]
		if !exists {
			return fmt.Errorf("unknown inherited profile %q", current)
		}
		for _, parent := range profile.Extends {
			if err := add(parent, append(append([]string{}, stack...), current)); err != nil {
				return err
			}
		}
		for _, value := range profile.PackageIDs {
			appendUnique(&result.packages, seenPackages, value)
		}
		for _, value := range profile.RecommendedPackIDs {
			appendUnique(&result.recommended, seenRecommended, value)
		}
		for _, value := range profile.OptionalPackIDs {
			appendUnique(&result.optional, seenOptional, value)
		}
		return nil
	}
	return result, add(id, nil)
}

func selectProvider(pkg catalog.Package, platform, architecture string) (catalog.Provider, error) {
	providers := pkg.Providers[platform]
	for _, provider := range providers {
		if len(provider.Architectures) == 0 || contains(provider.Architectures, architecture) {
			return provider, nil
		}
	}
	return catalog.Provider{}, fmt.Errorf("package %q has no %s/%s provider", pkg.ID, platform, architecture)
}

func deterministicPlanID(catalogHash string, input Input, selectedPacks []string) string {
	payload := strings.Join([]string{catalogHash, input.Platform, input.Architecture, input.ProfileID, fmt.Sprint(input.EssentialsOnly), strings.Join(selectedPacks, ",")}, "\x00")
	sum := sha256.Sum256([]byte(payload))
	hexValue := hex.EncodeToString(sum[:16])
	return fmt.Sprintf("%s-%s-%s-%s-%s", hexValue[0:8], hexValue[8:12], hexValue[12:16], hexValue[16:20], hexValue[20:32])
}

func appendUnique(values *[]string, seen map[string]bool, value string) {
	if value == "" || seen[value] {
		return
	}
	seen[value] = true
	*values = append(*values, value)
}

func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}
