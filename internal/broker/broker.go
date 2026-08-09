package broker

import (
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/cowebsLB/cowebs-developer-setup/internal/adapter/windows"
	"github.com/cowebsLB/cowebs-developer-setup/internal/catalog"
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
	SessionID       string
	Plan            *planner.Plan
	Catalogs        *catalog.Catalogs
	DryRun          bool
	OutStream       io.Writer
	EventSink       func(Event) error
	StartSequence   int
	TerminalInstall map[string]bool
}

type Broker struct {
	winAdapter *windows.Adapter
	sequence   int
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

func (b *Broker) Execute(req ExecutionRequest) error {
	if err := planner.ValidateCanonical(req.Catalogs, req.Plan); err != nil {
		return fmt.Errorf("broker security violation: %w", err)
	}
	if req.Plan.Platform != "windows" {
		return fmt.Errorf("broker security violation: Windows broker cannot execute platform %q", req.Plan.Platform)
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
