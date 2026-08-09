package catalog

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
)

func Load(packagePath, profilePath string) (*Catalogs, error) {
	packageBytes, err := os.ReadFile(packagePath)
	if err != nil {
		return nil, fmt.Errorf("read package catalog: %w", err)
	}
	profileBytes, err := os.ReadFile(profilePath)
	if err != nil {
		return nil, fmt.Errorf("read profile catalog: %w", err)
	}

	var packages PackageCatalog
	if err := decodeStrict(packageBytes, &packages); err != nil {
		return nil, fmt.Errorf("decode package catalog: %w", err)
	}
	var profiles ProfileCatalog
	if err := decodeStrict(profileBytes, &profiles); err != nil {
		return nil, fmt.Errorf("decode profile catalog: %w", err)
	}

	catalogs := &Catalogs{
		Packages:    packages,
		Profiles:    profiles,
		PackageByID: make(map[string]Package, len(packages.Packages)),
		PackByID:    make(map[string]Pack, len(profiles.Packs)),
		ProfileByID: make(map[string]Profile, len(profiles.Profiles)),
	}
	if err := catalogs.validate(); err != nil {
		return nil, err
	}

	hash := sha256.New()
	hash.Write(packageBytes)
	hash.Write([]byte{0})
	hash.Write(profileBytes)
	catalogs.CatalogSHA256 = hex.EncodeToString(hash.Sum(nil))
	return catalogs, nil
}

func decodeStrict(data []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return fmt.Errorf("multiple JSON values are not allowed")
		}
		return err
	}
	return nil
}

func (c *Catalogs) validate() error {
	if c.Packages.SchemaVersion != 3 || c.Profiles.SchemaVersion != 3 {
		return fmt.Errorf("schema version 3 catalogs are required")
	}
	for _, pkg := range c.Packages.Packages {
		if pkg.ID == "" {
			return fmt.Errorf("package catalog contains an empty id")
		}
		if _, exists := c.PackageByID[pkg.ID]; exists {
			return fmt.Errorf("duplicate package id %q", pkg.ID)
		}
		if len(pkg.Providers) == 0 {
			return fmt.Errorf("package %q has no providers", pkg.ID)
		}
		for platform, providers := range pkg.Providers {
			if len(providers) == 0 {
				return fmt.Errorf("package %q has no providers for %s", pkg.ID, platform)
			}
			for _, provider := range providers {
				if provider.Manager == "" || provider.PackageID == "" || provider.Privilege == "" || provider.Scope == "" {
					return fmt.Errorf("package %q has an incomplete provider for %s", pkg.ID, platform)
				}
				if provider.Detection.Type != "manager-native" {
					return fmt.Errorf("package %q has unsupported detection type %q", pkg.ID, provider.Detection.Type)
				}
				if err := validateEstimate(pkg.ID, provider.Estimate); err != nil {
					return err
				}
			}
		}
		c.PackageByID[pkg.ID] = pkg
	}
	for _, pkg := range c.Packages.Packages {
		for _, id := range append(append([]string{}, pkg.Dependencies...), pkg.Conflicts...) {
			if _, exists := c.PackageByID[id]; !exists {
				return fmt.Errorf("package %q references unknown package %q", pkg.ID, id)
			}
		}
		for _, conflict := range pkg.Conflicts {
			if !contains(c.PackageByID[conflict].Conflicts, pkg.ID) {
				return fmt.Errorf("package conflict %q -> %q is not symmetric", pkg.ID, conflict)
			}
		}
	}
	for _, pack := range c.Profiles.Packs {
		if pack.ID == "" {
			return fmt.Errorf("profile catalog contains a pack with an empty id")
		}
		if _, exists := c.PackByID[pack.ID]; exists {
			return fmt.Errorf("duplicate pack id %q", pack.ID)
		}
		if err := c.validatePackageIDs("pack "+pack.ID, pack.PackageIDs); err != nil {
			return err
		}
		c.PackByID[pack.ID] = pack
	}
	for _, profile := range c.Profiles.Profiles {
		if profile.ID == "" {
			return fmt.Errorf("profile catalog contains a profile with an empty id")
		}
		if _, exists := c.ProfileByID[profile.ID]; exists {
			return fmt.Errorf("duplicate profile id %q", profile.ID)
		}
		c.ProfileByID[profile.ID] = profile
	}
	if err := c.validatePackageIDs("core package list", c.Profiles.CorePackageIDs); err != nil {
		return err
	}
	for _, profile := range c.Profiles.Profiles {
		if err := c.validatePackageIDs("profile "+profile.ID, profile.PackageIDs); err != nil {
			return err
		}
		for _, packID := range append(append([]string{}, profile.RecommendedPackIDs...), profile.OptionalPackIDs...) {
			if _, exists := c.PackByID[packID]; !exists {
				return fmt.Errorf("profile %q references unknown pack %q", profile.ID, packID)
			}
		}
		for _, parent := range profile.Extends {
			if _, exists := c.ProfileByID[parent]; !exists {
				return fmt.Errorf("profile %q extends unknown profile %q", profile.ID, parent)
			}
		}
		if err := c.validateProfileGraph(profile.ID, nil); err != nil {
			return err
		}
	}
	return nil
}

func validateEstimate(packageID string, estimate Estimate) error {
	if estimate.DownloadMBMin < 0 || estimate.DownloadMBMax < estimate.DownloadMBMin || estimate.InstallMinutesMin < 0 || estimate.InstallMinutesMax < estimate.InstallMinutesMin {
		return fmt.Errorf("package %q has an invalid estimate range", packageID)
	}
	return nil
}

func (c *Catalogs) validatePackageIDs(context string, ids []string) error {
	for _, id := range ids {
		if _, exists := c.PackageByID[id]; !exists {
			return fmt.Errorf("%s references unknown package %q", context, id)
		}
	}
	return nil
}

func (c *Catalogs) validateProfileGraph(id string, stack []string) error {
	if contains(stack, id) {
		return fmt.Errorf("profile inheritance cycle: %v -> %s", stack, id)
	}
	profile := c.ProfileByID[id]
	for _, parent := range profile.Extends {
		if err := c.validateProfileGraph(parent, append(append([]string{}, stack...), id)); err != nil {
			return err
		}
	}
	return nil
}

func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}
