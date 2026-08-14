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
	platform := runtime.GOOS
	if runtime.GOOS == "linux" {
		if detected, err := detectLinuxDistribution(); err == nil {
			platform = detected
		}
	}
	report := &DoctorReport{
		Platform:     platform,
		Architecture: runtime.GOARCH,
		Healthy:      true,
		Checks:       []CheckResult{},
	}

	// Check 1: Platform Compatibility
	if platform == "windows" {
		report.Checks = append(report.Checks, CheckResult{
			Name:    "Platform OS",
			Passed:  true,
			Status:  "OK",
			Message: "Windows platform detected",
		})
	} else if platform == "ubuntu" || platform == "fedora" {
		report.Checks = append(report.Checks, CheckResult{
			Name:    "Platform OS",
			Passed:  true,
			Status:  "OK",
			Message: fmt.Sprintf("Supported %s Linux distribution detected", platform),
		})
	} else {
		report.Healthy = false
		report.Checks = append(report.Checks, CheckResult{Name: "Platform OS", Passed: false, Status: "FAIL", Message: fmt.Sprintf("Unsupported platform %s", platform)})
	}

	// Check 2: platform package managers
	if platform == "windows" {
		checkManager(report, "Winget Manager", "winget", true)
	} else if platform == "ubuntu" {
		checkManager(report, "APT Manager", "apt-get", true)
		checkManager(report, "dpkg Inventory", "dpkg-query", true)
		checkManager(report, "Snap Manager", "snap", false)
		checkManager(report, "Flatpak Manager", "flatpak", false)
		checkFlatpakRemote(report)
	} else if platform == "fedora" {
		checkManager(report, "DNF Manager", "dnf", true)
		checkManager(report, "Snap Manager", "snap", false)
		checkManager(report, "Flatpak Manager", "flatpak", false)
		checkFlatpakRemote(report)
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

func checkFlatpakRemote(report *DoctorReport) {
	path, err := exec.LookPath("flatpak")
	if err != nil {
		return
	}
	found := false
	for _, scope := range []string{"--user", "--system"} {
		output, commandErr := exec.Command(path, scope, "remotes", "--columns=name").Output()
		if commandErr == nil {
			for _, remote := range strings.Fields(string(output)) {
				if remote == "flathub" {
					found = true
				}
			}
		}
	}
	if found {
		report.Checks = append(report.Checks, CheckResult{Name: "Flathub Remote", Passed: true, Status: "OK", Message: "Flathub remote is available"})
	} else {
		report.Checks = append(report.Checks, CheckResult{Name: "Flathub Remote", Passed: true, Status: "WARNING", Message: "Flathub is missing; selected plans add it through a typed scoped prerequisite"})
	}
}

func checkManager(report *DoctorReport, name, executable string, required bool) {
	path, err := exec.LookPath(executable)
	if err == nil {
		report.Checks = append(report.Checks, CheckResult{Name: name, Passed: true, Status: "OK", Message: fmt.Sprintf("%s found: %s", executable, path)})
		return
	}
	status := "WARNING"
	message := fmt.Sprintf("Optional manager %s was not found; plans selecting it will install the reviewed native manager package", executable)
	passed := true
	if required {
		status, passed = "FAIL", false
		message = fmt.Sprintf("Required manager %s was not found on PATH", executable)
		report.Healthy = false
	}
	report.Checks = append(report.Checks, CheckResult{Name: name, Passed: passed, Status: status, Message: message})
}

func detectLinuxDistribution() (string, error) {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "ID=") {
			return strings.Trim(strings.TrimPrefix(line, "ID="), "\"'"), nil
		}
	}
	return "", fmt.Errorf("missing distribution ID")
}
