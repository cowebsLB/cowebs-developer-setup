package doctor

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/cowebsLB/cowebs-developer-setup/internal/catalog"
)

type CheckResult struct {
	Name    string `json:"name"`
	Passed  bool   `json:"passed"`
	Status  string `json:"status"` // "OK", "WARNING", "FAIL"
	Message string `json:"message"`
}

type DoctorReport struct {
	Platform     string        `json:"platform"`
	Architecture string        `json:"architecture"`
	Healthy      bool          `json:"healthy"`
	Checks       []CheckResult `json:"checks"`
}

type DiagnosticsOptions struct {
	PackagesPath string
	ProfilesPath string
}

func RunDiagnostics(opts DiagnosticsOptions) *DoctorReport {
	report := &DoctorReport{
		Platform:     runtime.GOOS,
		Architecture: runtime.GOARCH,
		Healthy:      true,
		Checks:       []CheckResult{},
	}

	// Check 1: Platform Compatibility
	if runtime.GOOS == "windows" {
		report.Checks = append(report.Checks, CheckResult{
			Name:    "Platform OS",
			Passed:  true,
			Status:  "OK",
			Message: "Windows platform detected",
		})
	} else {
		report.Checks = append(report.Checks, CheckResult{
			Name:    "Platform OS",
			Passed:  true,
			Status:  "WARNING",
			Message: fmt.Sprintf("Platform %s detected (Windows target)", runtime.GOOS),
		})
	}

	// Check 2: Winget Package Manager
	wingetPath, err := exec.LookPath("winget")
	if err == nil {
		out, errCmd := exec.Command(wingetPath, "--version").Output()
		ver := "available"
		if errCmd == nil && len(out) > 0 {
			ver = strings.TrimSpace(string(out))
		}
		report.Checks = append(report.Checks, CheckResult{
			Name:    "Winget Manager",
			Passed:  true,
			Status:  "OK",
			Message: fmt.Sprintf("Winget found: %s (%s)", wingetPath, ver),
		})
	} else {
		report.Healthy = false
		report.Checks = append(report.Checks, CheckResult{
			Name:    "Winget Manager",
			Passed:  false,
			Status:  "FAIL",
			Message: "Winget executable not found on PATH. Install Microsoft App Installer.",
		})
	}

	// Check 3: Workspace Directories
	home, errHome := os.UserHomeDir()
	if errHome == nil {
		missingDirs := []string{}
		for _, dir := range []string{"Projects", "Workspace", "Scripts"} {
			p := filepath.Join(home, dir)
			if _, errStat := os.Stat(p); os.IsNotExist(errStat) {
				missingDirs = append(missingDirs, dir)
			}
		}
		if len(missingDirs) == 0 {
			report.Checks = append(report.Checks, CheckResult{
				Name:    "Workspace Directories",
				Passed:  true,
				Status:  "OK",
				Message: "User workspace folders (Projects, Workspace, Scripts) exist",
			})
		} else {
			report.Checks = append(report.Checks, CheckResult{
				Name:    "Workspace Directories",
				Passed:  true,
				Status:  "WARNING",
				Message: fmt.Sprintf("User workspace folders missing: %v (will be created during setup)", missingDirs),
			})
		}
	} else {
		report.Checks = append(report.Checks, CheckResult{Name: "Workspace Directories", Passed: true, Status: "WARNING", Message: "Could not resolve the user home directory"})
	}

	// Check 4: Manifest Catalogs Integrity
	if (opts.PackagesPath == "") != (opts.ProfilesPath == "") {
		report.Healthy = false
		report.Checks = append(report.Checks, CheckResult{Name: "Catalog Integrity", Passed: false, Status: "FAIL", Message: "Both package and profile catalog paths are required for integrity validation"})
	} else if opts.PackagesPath != "" {
		_, errLoad := catalog.Load(opts.PackagesPath, opts.ProfilesPath)
		if errLoad == nil {
			report.Checks = append(report.Checks, CheckResult{
				Name:    "Catalog Integrity",
				Passed:  true,
				Status:  "OK",
				Message: "Schema-v3 package and profile catalogs loaded and validated cleanly",
			})
		} else {
			report.Healthy = false
			report.Checks = append(report.Checks, CheckResult{
				Name:    "Catalog Integrity",
				Passed:  false,
				Status:  "FAIL",
				Message: fmt.Sprintf("Catalog validation failed: %v", errLoad),
			})
		}
	}

	return report
}
