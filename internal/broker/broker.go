package broker

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"time"

	linuxadapter "github.com/cowebsLB/cowebs-developer-setup/internal/adapter/linux"
	"github.com/cowebsLB/cowebs-developer-setup/internal/adapter/windows"
	"github.com/cowebsLB/cowebs-developer-setup/internal/catalog"
	"github.com/cowebsLB/cowebs-developer-setup/internal/configuration"
	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

type Event struct {
	SchemaVersion    int    `json:"schemaVersion"`
	SessionID        string `json:"sessionId"`
	Sequence         int    `json:"sequence"`
	Timestamp        string `json:"timestamp"`
	Type             string `json:"type"`
	Status           string `json:"status"`
	OperationID      string `json:"operationId,omitempty"`
	LogicalPackageID string `json:"logicalPackageId,omitempty"`
	Provider         string `json:"provider,omitempty"`
	ExitCode         *int   `json:"exitCode,omitempty"`
	Message          string `json:"message"`
	RebootRequired   *bool  `json:"rebootRequired,omitempty"`
	Retryable        *bool  `json:"retryable,omitempty"`
}

type ExecutionRequest struct {
	SessionID          string
	Plan               *planner.Plan
	Catalogs           *catalog.Catalogs
	DryRun             bool
	OutStream          io.Writer
	EventSink          func(Event) error
	StartSequence      int
	TerminalInstall    map[string]bool
	TerminalOperations map[string]bool
	Privilege          string
	SkipConfiguration  bool
}

type Broker struct {
	winAdapter   *windows.Adapter
	linuxAdapter *linuxadapter.Adapter
	linuxConfig  *configuration.LinuxHandler
	sequence     int
}

func NewBroker(winAdapter *windows.Adapter) *Broker {
	if winAdapter == nil {
		winAdapter = windows.NewAdapter()
	}
	return &Broker{
		winAdapter: winAdapter,
		sequence:   0,
	}
}

func NewLinuxBroker(adapter *linuxadapter.Adapter, config *configuration.LinuxHandler) *Broker {
	if config == nil {
		config = configuration.NewLinuxHandler()
	}
	return &Broker{linuxAdapter: adapter, linuxConfig: config}
}

func (b *Broker) Execute(req ExecutionRequest) error {
	if err := planner.ValidateCanonical(req.Catalogs, req.Plan); err != nil {
		return fmt.Errorf("broker security violation: %w", err)
	}
	if req.Plan.Platform == "windows" {
		return b.executeWindows(req)
	}
	if req.Plan.Platform == linuxadapter.PlatformUbuntu || req.Plan.Platform == linuxadapter.PlatformFedora {
		return b.executeLinux(req)
	}
	return fmt.Errorf("broker security violation: unsupported execution platform %q", req.Plan.Platform)
}

func (b *Broker) executeWindows(req ExecutionRequest) error {
	if req.Privilege != "" && req.Privilege != "elevated" {
		return fmt.Errorf("broker security violation: Windows broker only accepts elevated operations")
	}
	if !req.DryRun {
		elevated, err := windows.IsElevated()
		if err != nil {
			return fmt.Errorf("broker security violation: failed to verify Windows elevation: %w", err)
		}
		if !elevated {
			return fmt.Errorf("broker security violation: real execution requires an elevated Windows process")
		}
	}
	if req.SessionID == "" {
		req.SessionID = "sess-" + req.Plan.PlanID[:8]
	}
	b.sequence = req.StartSequence
	detectedInstalled := make(map[string]bool)

	// Execute elevated operations
	for _, op := range req.Plan.Operations {
		if op.Privilege != "elevated" {
			continue
		}
		if op.Kind == "install" && req.TerminalInstall[op.ID] {
			continue
		}

		switch op.Kind {
		case "detect":
			if err := b.emitEvent(req, Event{
				Type:             "operation",
				Status:           "started",
				OperationID:      op.ID,
				LogicalPackageID: op.LogicalPackageID,
				Provider:         op.Manager,
				Message:          fmt.Sprintf("Detecting %s", op.LogicalPackageID),
			}); err != nil {
				return err
			}

			installed, err := b.winAdapter.Detect(op)
			if err != nil {
				_ = b.emitEvent(req, Event{
					Type:             "operation",
					Status:           "failed",
					OperationID:      op.ID,
					LogicalPackageID: op.LogicalPackageID,
					Provider:         op.Manager,
					Message:          fmt.Sprintf("Detection failed for %s: %v", op.LogicalPackageID, err),
				})
				return err
			}

			if installed {
				detectedInstalled[op.LogicalPackageID] = true
				if err := b.emitEvent(req, Event{
					Type:             "operation",
					Status:           "succeeded",
					OperationID:      op.ID,
					LogicalPackageID: op.LogicalPackageID,
					Provider:         op.Manager,
					Message:          fmt.Sprintf("%s is already installed", op.LogicalPackageID),
				}); err != nil {
					return err
				}
			} else {
				if err := b.emitEvent(req, Event{
					Type:             "operation",
					Status:           "planned",
					OperationID:      op.ID,
					LogicalPackageID: op.LogicalPackageID,
					Provider:         op.Manager,
					Message:          fmt.Sprintf("%s requires installation", op.LogicalPackageID),
				}); err != nil {
					return err
				}
			}

		case "install":
			if detectedInstalled[op.LogicalPackageID] {
				if err := b.emitEvent(req, Event{
					Type: "operation", Status: "skipped", OperationID: op.ID,
					LogicalPackageID: op.LogicalPackageID, Provider: op.Manager,
					Message: fmt.Sprintf("%s is already installed", op.LogicalPackageID),
				}); err != nil {
					return err
				}
				continue
			}

			if err := b.emitEvent(req, Event{
				Type:             "operation",
				Status:           "started",
				OperationID:      op.ID,
				LogicalPackageID: op.LogicalPackageID,
				Provider:         op.Manager,
				Message:          fmt.Sprintf("Installing %s", op.LogicalPackageID),
			}); err != nil {
				return err
			}

			exitCode, _, err := b.winAdapter.ExecuteInstall(op, req.DryRun)
			if err != nil || exitCode != 0 {
				code := exitCode
				_ = b.emitEvent(req, Event{
					Type:             "operation",
					Status:           "failed",
					OperationID:      op.ID,
					LogicalPackageID: op.LogicalPackageID,
					Provider:         op.Manager,
					ExitCode:         &code,
					Message:          fmt.Sprintf("Installation failed for %s with exit code %d", op.LogicalPackageID, exitCode),
				})
				return fmt.Errorf("operation %s failed with exit code %d: %v", op.ID, exitCode, err)
			}

			code := exitCode
			status := "succeeded"
			if req.DryRun {
				status = "planned"
			}
			if err := b.emitEvent(req, Event{
				Type:             "operation",
				Status:           status,
				OperationID:      op.ID,
				LogicalPackageID: op.LogicalPackageID,
				Provider:         op.Manager,
				ExitCode:         &code,
				Message:          fmt.Sprintf("Successfully processed %s", op.LogicalPackageID),
			}); err != nil {
				return err
			}
		}
	}

	return nil
}

func (b *Broker) executeLinux(req ExecutionRequest) error {
	privilege := req.Privilege
	if privilege == "" {
		privilege = "elevated"
	}
	if privilege != "elevated" && privilege != "user" {
		return fmt.Errorf("broker security violation: invalid Linux privilege partition %q", privilege)
	}
	if b.linuxAdapter == nil || b.linuxAdapter.Platform != req.Plan.Platform {
		return fmt.Errorf("broker security violation: a matching Linux adapter is required")
	}
	if !req.DryRun && privilege == "elevated" {
		elevated, err := linuxadapter.IsElevated()
		if err != nil || !elevated {
			return fmt.Errorf("broker security violation: real machine execution requires an elevated Linux process")
		}
	}
	if req.SessionID == "" {
		req.SessionID = "sess-" + req.Plan.PlanID[:8]
	}
	b.sequence = req.StartSequence
	detectedInstalled := make(map[string]bool)
	terminal := req.TerminalOperations
	if terminal == nil {
		terminal = req.TerminalInstall
	}

	for _, op := range req.Plan.Operations {
		if op.Privilege != privilege || terminal[op.ID] {
			continue
		}
		switch op.Kind {
		case "ensure-manager", "ensure-flatpak-remote", "ensure-repository-key", "ensure-apt-repository", "refresh-package-index":
			if err := b.emitEvent(req, startedEvent(op, "Applying typed prerequisite")); err != nil {
				return err
			}
			exitCode, _, err := b.linuxAdapter.ExecutePrerequisite(op, req.DryRun)
			if err != nil || exitCode != 0 {
				return b.operationFailure(req, op, exitCode, "Prerequisite failed", err)
			}
			if err := b.emitEvent(req, completedEvent(op, req.DryRun, exitCode, "Typed prerequisite processed")); err != nil {
				return err
			}
		case "detect":
			if err := b.emitEvent(req, startedEvent(op, "Detecting "+op.LogicalPackageID)); err != nil {
				return err
			}
			installed, err := b.linuxAdapter.Detect(op)
			if err != nil {
				return b.operationFailure(req, op, -1, "Detection failed", err)
			}
			if installed {
				detectedInstalled[op.LogicalPackageID] = true
				if err := b.emitEvent(req, completedEvent(op, false, 0, op.LogicalPackageID+" is already installed")); err != nil {
					return err
				}
			} else if err := b.emitEvent(req, Event{Type: "operation", Status: "planned", OperationID: op.ID, LogicalPackageID: op.LogicalPackageID, Provider: op.Manager, Message: op.LogicalPackageID + " requires installation"}); err != nil {
				return err
			}
		case "install":
			if detectedInstalled[op.LogicalPackageID] {
				if err := b.emitEvent(req, Event{Type: "operation", Status: "skipped", OperationID: op.ID, LogicalPackageID: op.LogicalPackageID, Provider: op.Manager, Message: op.LogicalPackageID + " is already installed"}); err != nil {
					return err
				}
				continue
			}
			if err := b.emitEvent(req, startedEvent(op, "Installing "+op.LogicalPackageID)); err != nil {
				return err
			}
			exitCode, _, err := b.linuxAdapter.ExecuteInstall(op, req.DryRun)
			if err != nil || exitCode != 0 {
				return b.operationFailure(req, op, exitCode, "Installation failed", err)
			}
			if err := b.emitEvent(req, completedEvent(op, req.DryRun, exitCode, "Successfully processed "+op.LogicalPackageID)); err != nil {
				return err
			}
		case "configure":
			if req.SkipConfiguration {
				if err := b.emitEvent(req, Event{Type: "configuration", Status: "skipped", OperationID: op.ID, LogicalPackageID: op.LogicalPackageID, Message: "Configuration disabled by explicit request"}); err != nil {
					return err
				}
				continue
			}
			if b.linuxConfig == nil {
				return fmt.Errorf("Linux configuration handler is required")
			}
			if err := b.emitEvent(req, startedEvent(op, "Applying configuration intent "+op.ConfigurationIntent)); err != nil {
				return err
			}
			err := b.linuxConfig.Execute(op, req.DryRun)
			var manual *configuration.ErrManualConfiguration
			if errors.As(err, &manual) {
				if emitErr := b.emitEvent(req, Event{Type: "configuration", Status: "skipped", OperationID: op.ID, LogicalPackageID: op.LogicalPackageID, Message: manual.Message}); emitErr != nil {
					return emitErr
				}
				continue
			}
			if err != nil {
				return b.operationFailure(req, op, -1, "Configuration failed", err)
			}
			if err := b.emitEvent(req, Event{Type: "configuration", Status: statusForRun(req.DryRun), OperationID: op.ID, LogicalPackageID: op.LogicalPackageID, Message: "Configuration intent processed: " + op.ConfigurationIntent}); err != nil {
				return err
			}
		default:
			return fmt.Errorf("unsupported Linux operation kind %q", op.Kind)
		}
	}
	return nil
}

func startedEvent(op planner.Operation, message string) Event {
	return Event{Type: "operation", Status: "started", OperationID: op.ID, LogicalPackageID: op.LogicalPackageID, Provider: op.Manager, Message: message}
}

func completedEvent(op planner.Operation, dryRun bool, exitCode int, message string) Event {
	code := exitCode
	return Event{Type: "operation", Status: statusForRun(dryRun), OperationID: op.ID, LogicalPackageID: op.LogicalPackageID, Provider: op.Manager, ExitCode: &code, Message: message}
}

func statusForRun(dryRun bool) string {
	if dryRun {
		return "planned"
	}
	return "succeeded"
}

func (b *Broker) operationFailure(req ExecutionRequest, op planner.Operation, exitCode int, message string, cause error) error {
	code := exitCode
	_ = b.emitEvent(req, Event{Type: "operation", Status: "failed", OperationID: op.ID, LogicalPackageID: op.LogicalPackageID, Provider: op.Manager, ExitCode: &code, Message: message + " for " + op.LogicalPackageID})
	if cause == nil {
		return fmt.Errorf("operation %s failed with exit code %d", op.ID, exitCode)
	}
	return fmt.Errorf("operation %s failed with exit code %d: %w", op.ID, exitCode, cause)
}

func (b *Broker) emitEvent(req ExecutionRequest, event Event) error {
	b.sequence++
	event.SchemaVersion = 1
	event.SessionID = req.SessionID
	event.Sequence = b.sequence
	if event.Timestamp == "" {
		event.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	if req.EventSink != nil {
		if err := req.EventSink(event); err != nil {
			return fmt.Errorf("failed to persist execution event: %w", err)
		}
	}
	if req.OutStream != nil {
		data, err := json.Marshal(event)
		if err != nil {
			return fmt.Errorf("failed to encode execution event: %w", err)
		}
		if _, err := fmt.Fprintln(req.OutStream, string(data)); err != nil {
			return fmt.Errorf("failed to write execution event: %w", err)
		}
	}
	return nil
}
