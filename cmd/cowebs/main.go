package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"

	linuxadapter "github.com/cowebsLB/cowebs-developer-setup/internal/adapter/linux"
	"github.com/cowebsLB/cowebs-developer-setup/internal/application"
	"github.com/cowebsLB/cowebs-developer-setup/internal/broker"
	"github.com/cowebsLB/cowebs-developer-setup/internal/doctor"
	"github.com/cowebsLB/cowebs-developer-setup/internal/journal"
	"github.com/cowebsLB/cowebs-developer-setup/internal/planner"
	"github.com/cowebsLB/cowebs-developer-setup/internal/release"
)

var version = "6.3.0-dev"

type stringList []string

func (values *stringList) String() string { return strings.Join(*values, ",") }
func (values *stringList) Set(value string) error {
	*values = append(*values, value)
	return nil
}

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		printUsage(stderr)
		return 2
	}
	if args[0] == "--version" || args[0] == "version" {
		fmt.Fprintf(stdout, "cowebs %s\n", version)
		return 0
	}
	var err error
	switch args[0] {
	case "plan":
		err = runPlan(args[1:], stdout, stderr)
	case "install":
		err = runInstall(args[1:], stdout, stderr, false)
	case "resume":
		err = runInstall(args[1:], stdout, stderr, true)
	case "status":
		err = runStatus(args[1:], stdout, stderr)
	case "doctor":
		err = runDoctor(args[1:], stdout, stderr)
	case "update":
		err = runUpdate(args[1:], stdout, stderr)
	case "completion":
		err = runCompletion(args[1:], stdout)
	case "internal-broker":
		err = runInternalBroker(args[1:], stdout, stderr)
	default:
		printUsage(stderr)
		return 2
	}
	if err != nil {
		fmt.Fprintln(stderr, "ERROR:", err)
		var unsupported *planner.UnsupportedPackagesError
		if errors.As(err, &unsupported) {
			return 3
		}
		return 1
	}
	return 0
}

func printUsage(out io.Writer) {
	fmt.Fprintln(out, "usage: cowebs <plan|install|status|resume|doctor> dev-setup [options]")
	fmt.Fprintln(out, "       cowebs update --manifest HTTPS_URL [--output FILE]")
	fmt.Fprintln(out, "       cowebs completion <bash|zsh|powershell>")
}

type planFlags struct {
	packages, profiles, profile, platform, architecture string
	essentialsOnly, jsonOutput                          bool
	packs                                               stringList
}

func addPlanFlags(flags *flag.FlagSet, values *planFlags) {
	flags.StringVar(&values.packages, "packages", "", "schema-v3 package catalog")
	flags.StringVar(&values.profiles, "profiles", "", "schema-v3 profile catalog")
	flags.StringVar(&values.profile, "profile", "", "developer profile")
	flags.StringVar(&values.platform, "platform", defaultPlatform(), "target platform")
	flags.StringVar(&values.architecture, "architecture", defaultArchitecture(), "target architecture")
	flags.BoolVar(&values.essentialsOnly, "essentials-only", false, "omit recommended packs")
	flags.BoolVar(&values.jsonOutput, "json", false, "output JSON")
	flags.Var(&values.packs, "pack", "explicit pack; repeatable")
}

func requireProduct(args []string) ([]string, error) {
	if len(args) == 0 || args[0] != "dev-setup" {
		return nil, fmt.Errorf("the stable product identifier dev-setup is required")
	}
	return args[1:], nil
}

func serviceFor(values *planFlags) (*application.Service, error) {
	packages, profiles, err := resolveCatalogPaths(values.packages, values.profiles)
	if err != nil {
		return nil, err
	}
	values.packages, values.profiles = packages, profiles
	return application.New(packages, profiles)
}

func buildPlan(service *application.Service, values planFlags) (*planner.Plan, error) {
	if values.profile == "" {
		return nil, fmt.Errorf("--profile is required")
	}
	return service.Plan(planner.Input{Platform: values.platform, Architecture: values.architecture, ProfileID: values.profile, ExplicitPackIDs: values.packs, EssentialsOnly: values.essentialsOnly})
}

func runPlan(args []string, stdout, stderr io.Writer) error {
	args, err := requireProduct(args)
	if err != nil {
		return err
	}
	flags := flag.NewFlagSet("cowebs plan dev-setup", flag.ContinueOnError)
	flags.SetOutput(stderr)
	var values planFlags
	addPlanFlags(flags, &values)
	if err := flags.Parse(args); err != nil {
		return err
	}
	service, err := serviceFor(&values)
	if err != nil {
		return err
	}
	plan, err := buildPlan(service, values)
	if err != nil {
		return err
	}
	if values.jsonOutput {
		encoder := json.NewEncoder(stdout)
		encoder.SetIndent("", "  ")
		return encoder.Encode(plan)
	}
	fmt.Fprintf(stdout, "COWebs dev-setup plan\nPlan: %s\nTarget: %s/%s\nProfile: %s\nOperations: %d\n", plan.PlanID, plan.Platform, plan.Architecture, plan.ProfileID, len(plan.Operations))
	return nil
}

func runInstall(args []string, stdout, stderr io.Writer, resume bool) error {
	args, err := requireProduct(args)
	if err != nil {
		return err
	}
	flags := flag.NewFlagSet("cowebs install dev-setup", flag.ContinueOnError)
	flags.SetOutput(stderr)
	var values planFlags
	addPlanFlags(flags, &values)
	dryRun := flags.Bool("dry-run", false, "plan execution without mutation")
	journalPath := flags.String("journal", "", "execution journal path")
	statePath := flags.String("state", "", "execution state path")
	planPath := flags.String("plan", "", "canonical plan path (required for resume)")
	planOutput := flags.String("plan-out", "", "write the canonical plan")
	nonInteractive := flags.Bool("non-interactive", false, "disable prompts")
	noConfig := flags.Bool("no-config", false, "skip all post-install configuration")
	_ = flags.Bool("no-restart", false, "do not request a restart")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if !resume && values.profile == "" && !*nonInteractive {
		fmt.Fprint(stdout, "Developer profile (backend, frontend, android, devops, ai, cyber, game, fullstack, everything): ")
		if _, err := fmt.Fscanln(os.Stdin, &values.profile); err != nil {
			return fmt.Errorf("read interactive profile: %w", err)
		}
	}
	service, err := serviceFor(&values)
	if err != nil {
		return err
	}
	var plan *planner.Plan
	if resume {
		if *planPath == "" || *journalPath == "" {
			return fmt.Errorf("resume requires --plan and --journal")
		}
		plan, err = application.LoadPlan(*planPath)
		if err == nil {
			err = planner.ValidateCanonical(service.Catalogs, plan)
		}
	} else {
		plan, err = buildPlan(service, values)
	}
	if err != nil {
		return err
	}
	if *planOutput != "" {
		if err := application.SavePlan(*planOutput, plan); err != nil {
			return err
		}
	}
	if *journalPath == "" {
		*journalPath, err = defaultJournalPath(plan.PlanID)
		if err != nil {
			return err
		}
	}
	if *statePath == "" {
		*statePath = *journalPath + ".state.json"
	}
	executionJournal := journal.New(*journalPath, *statePath)
	var state *journal.State
	if resume {
		state, err = executionJournal.LoadState()
		if err == nil {
			err = journal.ValidateForPlan(state, plan)
		}
	} else {
		if info, statErr := os.Stat(*journalPath); statErr == nil && info.Size() > 0 {
			return fmt.Errorf("journal already contains events; use resume or select a new path")
		}
		state = journal.NewState(plan, "sess-"+plan.PlanID[:8])
		err = executionJournal.SaveState(state)
	}
	if err != nil {
		return err
	}
	if err := executePlan(service, plan, executionJournal, state, *dryRun, *noConfig, stdout, stderr); err != nil {
		return err
	}
	loaded, err := executionJournal.LoadState()
	if err != nil {
		return err
	}
	if values.jsonOutput {
		encoder := json.NewEncoder(stdout)
		encoder.SetIndent("", "  ")
		return encoder.Encode(loaded)
	}
	fmt.Fprintf(stdout, "COWebs dev-setup %s completed. Completed: %d, skipped: %d, failed: %d\nJournal: %s\n", map[bool]string{true: "resume", false: "installation"}[resume], len(loaded.CompletedOperations), len(loaded.SkippedOperations), len(loaded.FailedOperations), *journalPath)
	return nil
}

func executePlan(service *application.Service, plan *planner.Plan, executionJournal *journal.Journal, state *journal.State, dryRun, skipConfiguration bool, stdout, stderr io.Writer) error {
	terminal := application.TerminalOperations(state)
	if plan.Platform == "windows" {
		if !dryRun {
			return fmt.Errorf("public Windows Go-runtime cutover remains gated; use master-setup.bat or --dry-run")
		}
		return service.ExecutePartition(plan, application.ExecutionOptions{SessionID: state.SessionID, Privilege: "elevated", DryRun: true, Journal: executionJournal, State: state, TerminalOperations: terminal, SkipConfiguration: skipConfiguration})
	}
	if runtime.GOOS != "linux" {
		return fmt.Errorf("%s execution requires a matching Linux host", plan.Platform)
	}
	actual, err := detectLinuxPlatform()
	if err != nil || actual != plan.Platform {
		return fmt.Errorf("plan target %s does not match this Linux host (%s): %w", plan.Platform, actual, err)
	}
	if dryRun {
		if err := service.ExecutePartition(plan, application.ExecutionOptions{SessionID: state.SessionID, Privilege: "elevated", DryRun: true, Journal: executionJournal, State: state, TerminalOperations: terminal, SkipConfiguration: skipConfiguration}); err != nil {
			return err
		}
		return service.ExecutePartition(plan, application.ExecutionOptions{SessionID: state.SessionID, Privilege: "user", DryRun: true, Journal: executionJournal, State: state, TerminalOperations: application.TerminalOperations(state), SkipConfiguration: skipConfiguration})
	}
	elevated, _ := linuxadapter.IsElevated()
	if elevated {
		return fmt.Errorf("run cowebs install as the target desktop user; the controller performs one sudo handoff for machine operations")
	}
	if err := runElevatedPartition(service, plan, state, executionJournal, stderr); err != nil {
		return err
	}
	return service.ExecutePartition(plan, application.ExecutionOptions{SessionID: state.SessionID, Privilege: "user", DryRun: false, Journal: executionJournal, State: state, TerminalOperations: application.TerminalOperations(state), OutStream: nil, SkipConfiguration: skipConfiguration})
}

func runElevatedPartition(service *application.Service, plan *planner.Plan, state *journal.State, executionJournal *journal.Journal, stderr io.Writer) error {
	temporary, err := os.CreateTemp("", "cowebs-plan-*.json")
	if err != nil {
		return err
	}
	planPath := temporary.Name()
	_ = temporary.Close()
	defer os.Remove(planPath)
	if err := application.SavePlan(planPath, plan); err != nil {
		return err
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	arguments := []string{executable, "internal-broker", "dev-setup", "--plan", planPath, "--packages", service.PackagesPath, "--profiles", service.ProfilesPath, "--session", state.SessionID, "--start-sequence", strconv.Itoa(state.LastSequence)}
	for _, operationID := range append(append([]string{}, state.CompletedOperations...), state.SkippedOperations...) {
		arguments = append(arguments, "--terminal", operationID)
	}
	command := exec.Command("sudo", arguments...)
	prepareInterruptibleChild(command)
	output, err := command.StdoutPipe()
	if err != nil {
		return fmt.Errorf("open privileged broker event stream: %w", err)
	}
	command.Stderr = stderr
	command.Stdin = os.Stdin
	if err := command.Start(); err != nil {
		return fmt.Errorf("single privileged handoff failed: %w", err)
	}
	interrupts := make(chan os.Signal, 1)
	brokerDone := make(chan struct{})
	signal.Notify(interrupts, os.Interrupt)
	defer signal.Stop(interrupts)
	defer close(brokerDone)
	go func() {
		select {
		case interrupt := <-interrupts:
			interruptChild(command, interrupt, brokerDone)
		case <-brokerDone:
		}
	}()
	if err := persistChildEventStream(output, executionJournal, state, plan); err != nil {
		_ = command.Process.Kill()
		_ = command.Wait()
		return err
	}
	if err := command.Wait(); err != nil {
		return fmt.Errorf("single privileged handoff failed after persisting completed operations: %w", err)
	}
	return nil
}

func persistChildEvents(data []byte, executionJournal *journal.Journal, state *journal.State, plan *planner.Plan) error {
	return persistChildEventStream(bytes.NewReader(data), executionJournal, state, plan)
}

func persistChildEventStream(stream io.Reader, executionJournal *journal.Journal, state *journal.State, plan *planner.Plan) error {
	knownOperations := make(map[string]bool, len(plan.Operations))
	for _, operation := range plan.Operations {
		knownOperations[operation.ID] = true
	}
	scanner := bufio.NewScanner(stream)
	for scanner.Scan() {
		decoder := json.NewDecoder(bytes.NewReader(scanner.Bytes()))
		decoder.DisallowUnknownFields()
		var event broker.Event
		if err := decoder.Decode(&event); err != nil {
			return fmt.Errorf("privileged broker returned invalid event data: %w", err)
		}
		var trailing any
		if err := decoder.Decode(&trailing); err != io.EOF {
			return fmt.Errorf("privileged broker returned trailing event data")
		}
		if event.SessionID != state.SessionID || event.Sequence <= state.LastSequence || (event.OperationID != "" && !knownOperations[event.OperationID]) {
			return fmt.Errorf("privileged broker returned an event outside the canonical session or plan")
		}
		if err := executionJournal.AppendEvent(event); err != nil {
			return err
		}
		journal.ApplyEvent(state, event)
		if err := executionJournal.SaveState(state); err != nil {
			return err
		}
	}
	return scanner.Err()
}

func runInternalBroker(args []string, stdout, stderr io.Writer) error {
	args, err := requireProduct(args)
	if err != nil {
		return err
	}
	flags := flag.NewFlagSet("internal-broker", flag.ContinueOnError)
	flags.SetOutput(stderr)
	planPath := flags.String("plan", "", "canonical plan")
	packages := flags.String("packages", "", "package catalog")
	profiles := flags.String("profiles", "", "profile catalog")
	session := flags.String("session", "", "session id")
	startSequence := flags.Int("start-sequence", 0, "starting event sequence")
	dryRun := flags.Bool("dry-run", false, "dry run")
	var terminalIDs stringList
	flags.Var(&terminalIDs, "terminal", "already-completed operation; repeatable")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *planPath == "" || *packages == "" || *profiles == "" || *session == "" {
		return fmt.Errorf("internal broker requires plan, catalogs, and session")
	}
	service, err := application.New(*packages, *profiles)
	if err != nil {
		return err
	}
	plan, err := application.LoadPlan(*planPath)
	if err != nil {
		return err
	}
	state := journal.NewState(plan, *session)
	state.LastSequence = *startSequence
	terminal := make(map[string]bool, len(terminalIDs))
	for _, id := range terminalIDs {
		terminal[id] = true
	}
	return service.ExecutePartition(plan, application.ExecutionOptions{SessionID: *session, Privilege: "elevated", DryRun: *dryRun, OutStream: stdout, State: state, TerminalOperations: terminal})
}

func runStatus(args []string, stdout, stderr io.Writer) error {
	args, err := requireProduct(args)
	if err != nil {
		return err
	}
	flags := flag.NewFlagSet("status", flag.ContinueOnError)
	flags.SetOutput(stderr)
	journalPath := flags.String("journal", "", "journal path")
	statePath := flags.String("state", "", "state path")
	jsonOutput := flags.Bool("json", false, "output JSON")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *journalPath == "" && *statePath == "" {
		return fmt.Errorf("--journal or --state is required")
	}
	if *statePath == "" {
		*statePath = *journalPath + ".state.json"
	}
	state, err := journal.New(*journalPath, *statePath).LoadState()
	if err != nil {
		return err
	}
	if *jsonOutput {
		encoder := json.NewEncoder(stdout)
		encoder.SetIndent("", "  ")
		return encoder.Encode(state)
	}
	fmt.Fprintf(stdout, "Session: %s\nPlan: %s\nCompleted: %d\nSkipped: %d\nFailed: %d\n", state.SessionID, state.PlanID, len(state.CompletedOperations), len(state.SkippedOperations), len(state.FailedOperations))
	return nil
}

func runDoctor(args []string, stdout, stderr io.Writer) error {
	args, err := requireProduct(args)
	if err != nil {
		return err
	}
	flags := flag.NewFlagSet("doctor", flag.ContinueOnError)
	flags.SetOutput(stderr)
	packages := flags.String("packages", "", "package catalog")
	profiles := flags.String("profiles", "", "profile catalog")
	jsonOutput := flags.Bool("json", false, "output JSON")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if (*packages == "") != (*profiles == "") {
		return fmt.Errorf("both package and profile catalogs are required")
	}
	report := doctor.RunDiagnostics(doctor.DiagnosticsOptions{PackagesPath: *packages, ProfilesPath: *profiles})
	if *jsonOutput {
		encoder := json.NewEncoder(stdout)
		encoder.SetIndent("", "  ")
		if err := encoder.Encode(report); err != nil {
			return err
		}
	} else {
		for _, check := range report.Checks {
			fmt.Fprintf(stdout, "[%s] %s: %s\n", check.Status, check.Name, check.Message)
		}
	}
	if !report.Healthy {
		return fmt.Errorf("system diagnostics found blocking issues")
	}
	return nil
}

func runUpdate(args []string, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("update", flag.ContinueOnError)
	flags.SetOutput(stderr)
	manifestURL := flags.String("manifest", "", "immutable HTTPS release-manifest URL")
	output := flags.String("output", "", "verified artifact destination")
	platform := flags.String("platform", releasePlatform(), "artifact platform")
	architecture := flags.String("architecture", defaultArchitecture(), "artifact architecture")
	check := flags.Bool("check", false, "verify manifest without downloading")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *manifestURL == "" {
		return fmt.Errorf("--manifest is required")
	}
	client := release.NewClient()
	manifest, err := client.LoadManifest(*manifestURL)
	if err != nil {
		return err
	}
	artifact, err := manifest.Select(*platform, *architecture)
	if err != nil {
		return err
	}
	if *check {
		fmt.Fprintf(stdout, "Update %s available: %s (%s)\n", manifest.Version, artifact.Name, artifact.SHA256)
		return nil
	}
	if *output == "" {
		return fmt.Errorf("--output is required unless --check is used; in-place executable replacement is intentionally not implicit")
	}
	if err := client.DownloadVerified(artifact, *output); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Verified %s to %s\n", artifact.Name, *output)
	return nil
}

func runCompletion(args []string, stdout io.Writer) error {
	if len(args) != 1 {
		return fmt.Errorf("completion requires bash, zsh, or powershell")
	}
	switch args[0] {
	case "bash", "zsh":
		fmt.Fprintln(stdout, "complete -W 'plan install status resume doctor update completion version' cowebs")
	case "powershell":
		fmt.Fprintln(stdout, "Register-ArgumentCompleter -Native -CommandName cowebs -ScriptBlock { param($wordToComplete) 'plan','install','status','resume','doctor','update','completion','version' | Where-Object { $_ -like \"$wordToComplete*\" } }")
	default:
		return fmt.Errorf("unsupported completion shell %q", args[0])
	}
	return nil
}

func resolveCatalogPaths(packages, profiles string) (string, string, error) {
	if packages != "" || profiles != "" {
		if packages == "" || profiles == "" {
			return "", "", fmt.Errorf("both --packages and --profiles are required")
		}
		return packages, profiles, nil
	}
	executable, err := os.Executable()
	if err != nil {
		return "", "", err
	}
	directory := filepath.Join(filepath.Dir(executable), "catalog")
	packages = filepath.Join(directory, "package-catalog.v3.json")
	profiles = filepath.Join(directory, "profile-catalog.v3.json")
	if _, err := os.Stat(packages); err == nil {
		return packages, profiles, nil
	}
	if dataHome, err := linuxUserDataHome(); err == nil && dataHome != "" {
		candidatePackages := filepath.Join(dataHome, "cowebs", "catalog", "package-catalog.v3.json")
		candidateProfiles := filepath.Join(dataHome, "cowebs", "catalog", "profile-catalog.v3.json")
		if _, err := os.Stat(candidatePackages); err == nil {
			return candidatePackages, candidateProfiles, nil
		}
	}
	for _, sharedDirectory := range []string{"/usr/local/share/cowebs/catalog", "/usr/share/cowebs/catalog"} {
		candidatePackages := filepath.Join(sharedDirectory, "package-catalog.v3.json")
		candidateProfiles := filepath.Join(sharedDirectory, "profile-catalog.v3.json")
		if _, err := os.Stat(candidatePackages); err == nil {
			return candidatePackages, candidateProfiles, nil
		}
	}
	return "", "", fmt.Errorf("bundled catalogs were not found; provide --packages and --profiles")
}

func linuxUserDataHome() (string, error) {
	if runtime.GOOS != "linux" {
		return "", nil
	}
	if configured := strings.TrimSpace(os.Getenv("XDG_DATA_HOME")); configured != "" {
		if !filepath.IsAbs(configured) {
			return "", fmt.Errorf("XDG_DATA_HOME must be absolute")
		}
		return configured, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".local", "share"), nil
}

func defaultJournalPath(planID string) (string, error) {
	base, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, "cowebs", "dev-setup", "sessions", planID+".jsonl"), nil
}

func defaultPlatform() string {
	if runtime.GOOS == "windows" {
		return "windows"
	}
	if runtime.GOOS == "linux" {
		if platform, err := detectLinuxPlatform(); err == nil {
			return platform
		}
	}
	return runtime.GOOS
}

func detectLinuxPlatform() (string, error) {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "ID=") {
			value := strings.Trim(strings.TrimPrefix(line, "ID="), "\"'")
			if value == "ubuntu" || value == "fedora" {
				return value, nil
			}
			return value, fmt.Errorf("unsupported Linux distribution")
		}
	}
	return "", fmt.Errorf("/etc/os-release has no distribution ID")
}

func defaultArchitecture() string {
	switch runtime.GOARCH {
	case "amd64":
		return "x64"
	case "386":
		return "x86"
	default:
		return runtime.GOARCH
	}
}

func releasePlatform() string {
	if runtime.GOOS == "linux" {
		return "linux"
	}
	return runtime.GOOS
}
