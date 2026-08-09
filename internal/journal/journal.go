package journal

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/cowebsLB/cowebs-developer-setup/internal/broker"
	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

type State struct {
	SessionID           string            `json:"sessionId"`
	PlanID              string            `json:"planId"`
	CatalogSHA256       string            `json:"catalogSha256"`
	Platform            string            `json:"platform"`
	Architecture        string            `json:"architecture"`
	ProfileID           string            `json:"profileId"`
	TotalOperations     int               `json:"totalOperations"`
	CompletedOperations []string          `json:"completedOperations"`
	SkippedOperations   []string          `json:"skippedOperations"`
	FailedOperations    []string          `json:"failedOperations"`
	OperationStatus     map[string]string `json:"operationStatus"`
	LastSequence        int               `json:"lastSequence"`
	RebootRequired      bool              `json:"rebootRequired"`
	UpdatedAt           string            `json:"updatedAt"`
}

type Journal struct {
	JournalPath string
	StatePath   string
	mu          sync.Mutex
	sequence    int
}

func New(journalPath, statePath string) *Journal {
	return &Journal{
		JournalPath: journalPath,
		StatePath:   statePath,
		sequence:    0,
	}
}

func (j *Journal) AppendEvent(ev broker.Event) error {
	j.mu.Lock()
	defer j.mu.Unlock()
	if j.JournalPath == "" {
		return fmt.Errorf("journal path is required")
	}
	if j.sequence == 0 {
		events, err := j.readEventsUnlocked()
		if err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("failed to inspect existing journal: %w", err)
		}
		for _, existing := range events {
			if existing.Sequence > j.sequence {
				j.sequence = existing.Sequence
			}
		}
	}

	if ev.SchemaVersion == 0 {
		ev.SchemaVersion = 1
	}
	if ev.Sequence == 0 {
		ev.Sequence = j.sequence + 1
	}
	if ev.Sequence <= j.sequence {
		return fmt.Errorf("event sequence %d is not greater than journal sequence %d", ev.Sequence, j.sequence)
	}
	j.sequence = ev.Sequence
	if ev.Timestamp == "" {
		ev.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	if _, err := decodeEventMustSequence(ev); err != nil {
		return err
	}

	data, err := json.Marshal(ev)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	dir := filepath.Dir(j.JournalPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create journal directory: %w", err)
	}

	file, err := os.OpenFile(j.JournalPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed to open journal file: %w", err)
	}
	defer file.Close()

	if _, err := file.Write(append(data, '\n')); err != nil {
		return fmt.Errorf("failed to write event to journal: %w", err)
	}
	if err := file.Sync(); err != nil {
		return fmt.Errorf("failed to flush event journal: %w", err)
	}

	return nil
}

func (j *Journal) ReadEvents() ([]broker.Event, error) {
	j.mu.Lock()
	defer j.mu.Unlock()

	file, err := os.Open(j.JournalPath)
	if err != nil {
		if os.IsNotExist(err) {
			return []broker.Event{}, nil
		}
		return nil, fmt.Errorf("failed to open journal file: %w", err)
	}
	defer file.Close()

	var events []broker.Event
	scanner := bufio.NewScanner(file)
	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		ev, err := decodeEvent([]byte(line))
		if err != nil {
			return nil, fmt.Errorf("invalid event at line %d: %w", lineNo, err)
		}
		events = append(events, ev)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("failed scanning journal file: %w", err)
	}

	return events, nil
}

func BuildStateFromEvents(events []broker.Event) *State {
	state := &State{
		OperationStatus:     make(map[string]string),
		CompletedOperations: []string{},
		SkippedOperations:   []string{},
		FailedOperations:    []string{},
	}

	for _, ev := range events {
		ApplyEvent(state, ev)
	}

	state.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	return state
}

func NewState(plan *planner.Plan, sessionID string) *State {
	return &State{
		SessionID: sessionID, PlanID: plan.PlanID, CatalogSHA256: plan.CatalogSHA256,
		Platform: plan.Platform, Architecture: plan.Architecture, ProfileID: plan.ProfileID,
		TotalOperations: len(plan.Operations), OperationStatus: make(map[string]string),
		CompletedOperations: []string{}, SkippedOperations: []string{}, FailedOperations: []string{},
	}
}

func ApplyEvent(state *State, ev broker.Event) {
	if ev.Sequence > state.LastSequence {
		state.LastSequence = ev.Sequence
	}
	if ev.SessionID != "" {
		state.SessionID = ev.SessionID
	}
	if ev.OperationID == "" {
		return
	}
	state.OperationStatus[ev.OperationID] = ev.Status
	switch ev.Status {
	case "succeeded":
		state.CompletedOperations = appendUnique(state.CompletedOperations, ev.OperationID)
		state.SkippedOperations = remove(state.SkippedOperations, ev.OperationID)
		state.FailedOperations = remove(state.FailedOperations, ev.OperationID)
	case "skipped":
		state.SkippedOperations = appendUnique(state.SkippedOperations, ev.OperationID)
		state.CompletedOperations = remove(state.CompletedOperations, ev.OperationID)
		state.FailedOperations = remove(state.FailedOperations, ev.OperationID)
	case "failed":
		state.FailedOperations = appendUnique(state.FailedOperations, ev.OperationID)
		state.CompletedOperations = remove(state.CompletedOperations, ev.OperationID)
		state.SkippedOperations = remove(state.SkippedOperations, ev.OperationID)
	}
	state.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
}

func ValidateForPlan(state *State, plan *planner.Plan) error {
	if state == nil {
		return fmt.Errorf("execution state is required")
	}
	if state.SessionID == "" {
		return fmt.Errorf("execution state has no session ID")
	}
	if state.LastSequence < 0 || state.OperationStatus == nil {
		return fmt.Errorf("execution state is structurally incomplete")
	}
	if state.PlanID != plan.PlanID || state.CatalogSHA256 != plan.CatalogSHA256 ||
		state.Platform != plan.Platform || state.Architecture != plan.Architecture ||
		state.ProfileID != plan.ProfileID || state.TotalOperations != len(plan.Operations) {
		return fmt.Errorf("execution state does not match the requested plan and catalog")
	}
	known := make(map[string]bool, len(plan.Operations))
	for _, op := range plan.Operations {
		known[op.ID] = true
	}
	seen := make(map[string]string)
	for status, ids := range map[string][]string{"succeeded": state.CompletedOperations, "skipped": state.SkippedOperations, "failed": state.FailedOperations} {
		for _, id := range ids {
			if !known[id] {
				return fmt.Errorf("execution state references unknown operation %q", id)
			}
			if prior := seen[id]; prior != "" {
				return fmt.Errorf("execution state records operation %q as both %s and %s", id, prior, status)
			}
			seen[id] = status
		}
	}
	return nil
}

func (j *Journal) SaveState(state *State) error {
	j.mu.Lock()
	defer j.mu.Unlock()
	if j.StatePath == "" {
		return fmt.Errorf("state path is required")
	}

	dir := filepath.Dir(j.StatePath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create state directory: %w", err)
	}

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal state: %w", err)
	}

	tmpPath := j.StatePath + ".tmp"
	file, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("failed opening temporary state file: %w", err)
	}
	if _, err = file.Write(append(data, '\n')); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("failed writing temporary state file: %w", err)
	}

	if err := os.Rename(tmpPath, j.StatePath); err != nil {
		os.Remove(tmpPath)
		return fmt.Errorf("failed committing state file: %w", err)
	}

	return nil
}

func (j *Journal) LoadState() (*State, error) {
	j.mu.Lock()
	defer j.mu.Unlock()

	if j.StatePath == "" {
		events, err := j.readEventsUnlocked()
		if err != nil {
			return nil, fmt.Errorf("failed to read journal: %w", err)
		}
		if len(events) == 0 {
			return nil, fmt.Errorf("journal contains no execution events")
		}
		return BuildStateFromEvents(events), nil
	}

	data, err := os.ReadFile(j.StatePath)
	if err != nil {
		if os.IsNotExist(err) {
			events, readErr := j.readEventsUnlocked()
			if readErr != nil || len(events) == 0 {
				return nil, fmt.Errorf("state file is unavailable and journal recovery failed: %w", err)
			}
			return BuildStateFromEvents(events), nil
		}
		return nil, fmt.Errorf("failed to read state file: %w", err)
	}

	var state State
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&state); err != nil {
		return nil, fmt.Errorf("failed to parse state file: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return nil, fmt.Errorf("failed to parse state file: multiple JSON values are not allowed")
		}
		return nil, fmt.Errorf("failed to parse state file: %w", err)
	}
	return &state, nil
}

func (j *Journal) readEventsUnlocked() ([]broker.Event, error) {
	if j.JournalPath == "" {
		return nil, os.ErrNotExist
	}
	file, err := os.Open(j.JournalPath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var events []broker.Event
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		ev, err := decodeEvent([]byte(line))
		if err != nil {
			return nil, err
		}
		events = append(events, ev)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return events, nil
}

func decodeEvent(data []byte) (broker.Event, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var ev broker.Event
	if err := decoder.Decode(&ev); err != nil {
		return ev, err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return ev, fmt.Errorf("multiple JSON values are not allowed")
		}
		return ev, err
	}
	if ev.SchemaVersion != 1 || ev.SessionID == "" || ev.Sequence < 1 || ev.Message == "" {
		return ev, fmt.Errorf("event is missing required schema-v1 fields")
	}
	if _, err := time.Parse(time.RFC3339, ev.Timestamp); err != nil {
		return ev, fmt.Errorf("event timestamp is invalid: %w", err)
	}
	if !contains([]string{"session", "plan", "operation", "configuration", "restart", "summary", "diagnostic"}, ev.Type) {
		return ev, fmt.Errorf("event has unsupported type %q", ev.Type)
	}
	if !contains([]string{"planned", "started", "succeeded", "skipped", "failed", "blocked", "retryable", "cancelled"}, ev.Status) {
		return ev, fmt.Errorf("event has unsupported status %q", ev.Status)
	}
	return ev, nil
}

func decodeEventMustSequence(ev broker.Event) (broker.Event, error) {
	data, err := json.Marshal(ev)
	if err != nil {
		return ev, err
	}
	return decodeEvent(data)
}

func appendUnique(slice []string, item string) []string {
	if item == "" || contains(slice, item) {
		return slice
	}
	return append(slice, item)
}

func contains(slice []string, item string) bool {
	for _, val := range slice {
		if val == item {
			return true
		}
	}
	return false
}

func remove(slice []string, item string) []string {
	var result []string
	for _, val := range slice {
		if val != item {
			result = append(result, val)
		}
	}
	return result
}
