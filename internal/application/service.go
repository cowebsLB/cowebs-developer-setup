package application

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"

	linuxadapter "github.com/cowebsLB/cowebs-developer-setup/internal/adapter/linux"
	"github.com/cowebsLB/cowebs-developer-setup/internal/broker"
	"github.com/cowebsLB/cowebs-developer-setup/internal/catalog"
	"github.com/cowebsLB/cowebs-developer-setup/internal/configuration"
	"github.com/cowebsLB/cowebs-developer-setup/internal/journal"
	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

// Service is the shared typed application boundary used by terminal and future
// GUI frontends. It owns catalog loading, planning, partitioned execution, and
// state persistence; frontends own only interaction and presentation.
type Service struct {
	Catalogs     *catalog.Catalogs
	PackagesPath string
	ProfilesPath string
}

func New(packagesPath, profilesPath string) (*Service, error) {
	catalogs, err := catalog.Load(packagesPath, profilesPath)
	if err != nil {
		return nil, err
	}
	return &Service{Catalogs: catalogs, PackagesPath: packagesPath, ProfilesPath: profilesPath}, nil
}

func (s *Service) Plan(input planner.Input) (*planner.Plan, error) {
	if s == nil || s.Catalogs == nil {
		return nil, fmt.Errorf("application service catalogs are required")
	}
	return planner.Build(s.Catalogs, input)
}

func LoadPlan(path string) (*planner.Plan, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read plan: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var plan planner.Plan
	if err := decoder.Decode(&plan); err != nil {
		return nil, fmt.Errorf("parse plan: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return nil, fmt.Errorf("parse plan: trailing JSON is not allowed")
	}
	return &plan, nil
}

func SavePlan(path string, plan *planner.Plan) error {
	data, err := json.MarshalIndent(plan, "", "  ")
	if err != nil {
		return err
	}
	return atomicWrite(path, append(data, '\n'), 0o600)
}

type ExecutionOptions struct {
	SessionID          string
	Privilege          string
	DryRun             bool
	OutStream          io.Writer
	Journal            *journal.Journal
	State              *journal.State
	TerminalOperations map[string]bool
	LinuxAdapter       *linuxadapter.Adapter
	LinuxConfiguration *configuration.LinuxHandler
	SkipConfiguration  bool
}

func (s *Service) ExecutePartition(plan *planner.Plan, options ExecutionOptions) error {
	if err := planner.ValidateCanonical(s.Catalogs, plan); err != nil {
		return err
	}
	var executor *broker.Broker
	if plan.Platform == "windows" {
		executor = broker.NewBroker(nil)
	} else {
		adapter := options.LinuxAdapter
		if adapter == nil {
			var err error
			adapter, err = linuxadapter.NewAdapter(plan.Platform)
			if err != nil {
				return err
			}
		}
		executor = broker.NewLinuxBroker(adapter, options.LinuxConfiguration)
	}

	state := options.State
	if state == nil {
		state = journal.NewState(plan, options.SessionID)
	}
	var sink func(broker.Event) error
	if options.Journal != nil {
		sink = func(event broker.Event) error {
			if err := options.Journal.AppendEvent(event); err != nil {
				return err
			}
			journal.ApplyEvent(state, event)
			return options.Journal.SaveState(state)
		}
	}
	return executor.Execute(broker.ExecutionRequest{
		SessionID:          options.SessionID,
		Plan:               plan,
		Catalogs:           s.Catalogs,
		DryRun:             options.DryRun,
		OutStream:          options.OutStream,
		EventSink:          sink,
		StartSequence:      state.LastSequence,
		TerminalOperations: options.TerminalOperations,
		Privilege:          options.Privilege,
		SkipConfiguration:  options.SkipConfiguration,
	})
}

func TerminalOperations(state *journal.State) map[string]bool {
	terminal := make(map[string]bool)
	if state == nil {
		return terminal
	}
	for _, id := range append(append([]string{}, state.CompletedOperations...), state.SkippedOperations...) {
		terminal[id] = true
	}
	return terminal
}

func atomicWrite(path string, data []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, data, mode); err != nil {
		return err
	}
	if err := os.Rename(temporary, path); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	return nil
}
