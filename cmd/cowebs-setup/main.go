package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/cowebsLB/cowebs-developer-setup/internal/broker"
	"github.com/cowebsLB/cowebs-developer-setup/internal/catalog"
	"github.com/cowebsLB/cowebs-developer-setup/internal/doctor"
	"github.com/cowebsLB/cowebs-developer-setup/internal/journal"
	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
)

type stringList []string

func (values *stringList) String() string { return fmt.Sprint([]string(*values)) }
func (values *stringList) Set(value string) error {
	*values = append(*values, value)
	return nil
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(2)
	}

	switch os.Args[1] {
	case "plan":
		runPlan(os.Args[2:])
	case "broker":
		runBroker(os.Args[2:])
	case "status":
		runStatus(os.Args[2:])
	case "resume":
		runResume(os.Args[2:])
	case "doctor":
		runDoctor(os.Args[2:])
	default:
		printUsage()
		os.Exit(2)
	}
}

func printUsage() {
	fmt.Fprintln(os.Stderr, "usage:")
	fmt.Fprintln(os.Stderr, "  cowebs-setup plan --packages FILE --profiles FILE --profile ID [--pack ID] [--essentials-only] [--json]")
	fmt.Fprintln(os.Stderr, "  cowebs-setup broker --plan FILE --packages FILE --profiles FILE [--dry-run] [--journal FILE] [--state FILE]")
	fmt.Fprintln(os.Stderr, "  cowebs-setup status [--journal FILE] [--state FILE] [--json]")
	fmt.Fprintln(os.Stderr, "  cowebs-setup resume --plan FILE --packages FILE --profiles FILE --journal FILE [--state FILE] [--dry-run] [--json]")
	fmt.Fprintln(os.Stderr, "  cowebs-setup doctor [--packages FILE] [--profiles FILE] [--json]")
}

func runPlan(args []string) {
	flags := flag.NewFlagSet("plan", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	packagesPath := flags.String("packages", "", "schema-v3 package catalog")
	profilesPath := flags.String("profiles", "", "schema-v3 profile catalog")
	profileID := flags.String("profile", "", "profile id")
	platform := flags.String("platform", "windows", "target platform")
	architecture := flags.String("architecture", "x64", "target architecture")
	essentialsOnly := flags.Bool("essentials-only", false, "omit recommended packs")
	jsonOutput := flags.Bool("json", true, "output json format")
	var packIDs stringList
	flags.Var(&packIDs, "pack", "explicit pack id; repeatable")
	if err := flags.Parse(args); err != nil {
		os.Exit(2)
	}
	if *packagesPath == "" || *profilesPath == "" || *profileID == "" {
		fmt.Fprintln(os.Stderr, "--packages, --profiles, and --profile are required")
		os.Exit(2)
	}

	catalogs, err := catalog.Load(*packagesPath, *profilesPath)
	if err != nil {
		fail(err)
	}
	plan, err := planner.Build(catalogs, planner.Input{
		Platform: *platform, Architecture: *architecture, ProfileID: *profileID,
		ExplicitPackIDs: packIDs, EssentialsOnly: *essentialsOnly,
	})
	if err != nil {
		fail(err)
	}

	if *jsonOutput {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetEscapeHTML(false)
		encoder.SetIndent("", "  ")
		if err := encoder.Encode(plan); err != nil {
			fail(err)
		}
	} else {
		fmt.Printf("Plan ID: %s\nProfile: %s\nOperations: %d\n", plan.PlanID, plan.ProfileID, len(plan.Operations))
	}
}

func runBroker(args []string) {
	flags := flag.NewFlagSet("broker", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	planPath := flags.String("plan", "", "execution plan v1 JSON file")
	packagesPath := flags.String("packages", "", "schema-v3 package catalog")
	profilesPath := flags.String("profiles", "", "schema-v3 profile catalog")
	journalPath := flags.String("journal", "", "optional journal JSONL output file")
	statePath := flags.String("state", "", "optional atomic state JSON file (defaults beside journal)")
	dryRun := flags.Bool("dry-run", false, "perform dry run without invoking installer")
	if err := flags.Parse(args); err != nil {
		os.Exit(2)
	}
	if *planPath == "" || *packagesPath == "" || *profilesPath == "" {
		fmt.Fprintln(os.Stderr, "--plan, --packages, and --profiles are required")
		os.Exit(2)
	}

	plan, err := loadPlan(*planPath)
	if err != nil {
		fail(err)
	}

	catalogs, err := catalog.Load(*packagesPath, *profilesPath)
	if err != nil {
		fail(err)
	}
	if err := planner.ValidateCanonical(catalogs, plan); err != nil {
		fail(err)
	}

	sessionID := "sess-" + plan.PlanID[:8]
	outStream := io.Writer(os.Stdout)
	var eventSink func(broker.Event) error
	if *journalPath != "" {
		if info, statErr := os.Stat(*journalPath); statErr == nil && info.Size() > 0 {
			fail(fmt.Errorf("journal already contains events; use resume or choose a new journal path"))
		} else if statErr != nil && !os.IsNotExist(statErr) {
			fail(fmt.Errorf("failed to inspect journal file: %w", statErr))
		}
		resolvedStatePath := resolveStatePath(*journalPath, *statePath)
		j := journal.New(*journalPath, resolvedStatePath)
		state := journal.NewState(plan, sessionID)
		eventSink = journalSink(j, state)
	}

	brk := broker.NewBroker(nil)
	req := broker.ExecutionRequest{
		SessionID: sessionID,
		Plan:      plan,
		Catalogs:  catalogs,
		DryRun:    *dryRun,
		OutStream: outStream,
		EventSink: eventSink,
	}

	if err := brk.Execute(req); err != nil {
		fail(err)
	}
}

func runStatus(args []string) {
	flags := flag.NewFlagSet("status", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	journalPath := flags.String("journal", "", "journal JSONL file path")
	statePath := flags.String("state", "", "state JSON file path")
	jsonOutput := flags.Bool("json", false, "output raw JSON format")
	if err := flags.Parse(args); err != nil {
		os.Exit(2)
	}

	if *journalPath == "" && *statePath == "" {
		fmt.Fprintln(os.Stderr, "either --journal or --state is required")
		os.Exit(2)
	}

	resolvedStatePath := *statePath
	if resolvedStatePath == "" && *journalPath != "" {
		resolvedStatePath = resolveStatePath(*journalPath, "")
	}
	j := journal.New(*journalPath, resolvedStatePath)
	st, err := j.LoadState()
	if err != nil {
		fail(fmt.Errorf("failed to load state: %w", err))
	}

	if *jsonOutput {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetIndent("", "  ")
		if err := encoder.Encode(st); err != nil {
			fail(err)
		}
		return
	}

	fmt.Println("COWebs.lb Execution Status")
	fmt.Printf("Session ID:  %s\n", st.SessionID)
	fmt.Printf("Last Seq:    %d\n", st.LastSequence)
	fmt.Printf("Completed:   %d\n", len(st.CompletedOperations))
	fmt.Printf("Skipped:     %d\n", len(st.SkippedOperations))
	fmt.Printf("Failed:      %d\n", len(st.FailedOperations))
	fmt.Printf("Updated At:  %s\n", st.UpdatedAt)
}

func runResume(args []string) {
	flags := flag.NewFlagSet("resume", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	planPath := flags.String("plan", "", "execution plan v1 JSON file")
	packagesPath := flags.String("packages", "", "schema-v3 package catalog")
	profilesPath := flags.String("profiles", "", "schema-v3 profile catalog")
	journalPath := flags.String("journal", "", "journal JSONL file path")
	statePath := flags.String("state", "", "state JSON file path")
	dryRun := flags.Bool("dry-run", false, "perform dry run without invoking installer")
	jsonOutput := flags.Bool("json", false, "output event stream in JSON format")
	if err := flags.Parse(args); err != nil {
		os.Exit(2)
	}

	if *planPath == "" || *packagesPath == "" || *profilesPath == "" || *journalPath == "" {
		fmt.Fprintln(os.Stderr, "--plan, --packages, --profiles, and --journal are required")
		os.Exit(2)
	}

	plan, err := loadPlan(*planPath)
	if err != nil {
		fail(err)
	}

	catalogs, err := catalog.Load(*packagesPath, *profilesPath)
	if err != nil {
		fail(err)
	}
	if err := planner.ValidateCanonical(catalogs, plan); err != nil {
		fail(err)
	}

	resolvedStatePath := resolveStatePath(*journalPath, *statePath)
	j := journal.New(*journalPath, resolvedStatePath)
	st, err := j.LoadState()
	if err != nil {
		fail(fmt.Errorf("failed to load resume state: %w", err))
	}
	if err := journal.ValidateForPlan(st, plan); err != nil {
		fail(err)
	}
	terminalInstall := make(map[string]bool)
	for _, opID := range append(append([]string{}, st.CompletedOperations...), st.SkippedOperations...) {
		terminalInstall[opID] = true
	}

	var outStream io.Writer
	if *jsonOutput {
		outStream = os.Stdout
	}

	brk := broker.NewBroker(nil)
	req := broker.ExecutionRequest{
		SessionID: st.SessionID, Plan: plan, Catalogs: catalogs, DryRun: *dryRun,
		OutStream: outStream, EventSink: journalSink(j, st), StartSequence: st.LastSequence,
		TerminalInstall: terminalInstall,
	}

	if err := brk.Execute(req); err != nil {
		fail(err)
	}

	if !*jsonOutput {
		fmt.Println("Resumed plan execution completed.")
	}
}

func runDoctor(args []string) {
	flags := flag.NewFlagSet("doctor", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	packagesPath := flags.String("packages", "", "optional schema-v3 package catalog")
	profilesPath := flags.String("profiles", "", "optional schema-v3 profile catalog")
	jsonOutput := flags.Bool("json", false, "output JSON format")
	if err := flags.Parse(args); err != nil {
		os.Exit(2)
	}

	report := doctor.RunDiagnostics(doctor.DiagnosticsOptions{
		PackagesPath: *packagesPath,
		ProfilesPath: *profilesPath,
	})

	if *jsonOutput {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetIndent("", "  ")
		if err := encoder.Encode(report); err != nil {
			fail(err)
		}
	} else {
		fmt.Println("COWebs.lb Setup System Doctor Diagnostics")
		fmt.Printf("Platform: %s / Architecture: %s\n\n", report.Platform, report.Architecture)
		for _, check := range report.Checks {
			fmt.Printf("[%s] %-24s : %s\n", check.Status, check.Name, check.Message)
		}
		if report.Healthy {
			fmt.Println("\nResult: System diagnostics passed cleanly.")
		} else {
			fmt.Println("\nResult: System diagnostics found issues that require attention.")
		}
	}

	if !report.Healthy {
		os.Exit(1)
	}
}

func loadPlan(path string) (*planner.Plan, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read plan file: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var plan planner.Plan
	if err := decoder.Decode(&plan); err != nil {
		return nil, fmt.Errorf("failed to parse plan JSON: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return nil, fmt.Errorf("failed to parse plan JSON: multiple JSON values are not allowed")
		}
		return nil, fmt.Errorf("failed to parse plan JSON: %w", err)
	}
	return &plan, nil
}

func resolveStatePath(journalPath, statePath string) string {
	if statePath != "" {
		return statePath
	}
	return journalPath + ".state.json"
}

func journalSink(j *journal.Journal, state *journal.State) func(broker.Event) error {
	return func(event broker.Event) error {
		if err := j.AppendEvent(event); err != nil {
			return err
		}
		journal.ApplyEvent(state, event)
		return j.SaveState(state)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "ERROR:", err)
	os.Exit(1)
}
