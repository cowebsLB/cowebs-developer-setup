package doctor

import (
	"testing"
)

func TestDoctorRunDiagnostics(t *testing.T) {
	report := RunDiagnostics(DiagnosticsOptions{})
	if report == nil {
		t.Fatalf("expected non-nil doctor report")
	}

	if len(report.Checks) == 0 {
		t.Fatalf("expected diagnostic checks to be executed")
	}

	hasPlatformCheck := false
	for _, check := range report.Checks {
		if check.Name == "Platform OS" {
			hasPlatformCheck = true
			break
		}
	}

	if !hasPlatformCheck {
		t.Errorf("expected Platform OS check in report")
	}
}
