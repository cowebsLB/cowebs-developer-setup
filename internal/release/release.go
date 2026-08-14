package release

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var (
	versionPattern = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$`)
	commitPattern  = regexp.MustCompile(`^[A-Fa-f0-9]{40}$`)
	digestPattern  = regexp.MustCompile(`^[A-Fa-f0-9]{64}$`)
)

type Manifest struct {
	SchemaVersion int        `json:"schemaVersion"`
	Version       string     `json:"version"`
	SourceCommit  string     `json:"sourceCommit"`
	PublishedAt   string     `json:"publishedAt"`
	Artifacts     []Artifact `json:"artifacts"`
}

type Artifact struct {
	Name                string `json:"name"`
	Platform            string `json:"platform"`
	Architecture        string `json:"architecture"`
	URL                 string `json:"url"`
	SHA256              string `json:"sha256"`
	SizeBytes           int64  `json:"sizeBytes"`
	MinimumEnvironment  string `json:"minimumEnvironment"`
	Signature           string `json:"signature,omitempty"`
	CertificateIdentity string `json:"certificateIdentity,omitempty"`
}

type Client struct {
	HTTP *http.Client
}

func NewClient() *Client { return &Client{HTTP: &http.Client{Timeout: 45 * time.Second}} }

func (c *Client) LoadManifest(address string) (*Manifest, error) {
	if err := validateImmutableHTTPS(address); err != nil {
		return nil, err
	}
	data, err := c.download(address, 2*1024*1024)
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var manifest Manifest
	if err := decoder.Decode(&manifest); err != nil {
		return nil, fmt.Errorf("parse release manifest: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return nil, fmt.Errorf("parse release manifest: trailing JSON is not allowed")
	}
	if err := ValidateManifest(&manifest); err != nil {
		return nil, err
	}
	return &manifest, nil
}

func ValidateManifest(manifest *Manifest) error {
	if manifest == nil || manifest.SchemaVersion != 1 {
		return fmt.Errorf("release manifest schema version 1 is required")
	}
	if !versionPattern.MatchString(manifest.Version) || !commitPattern.MatchString(manifest.SourceCommit) {
		return fmt.Errorf("release manifest has an invalid version or source commit")
	}
	if _, err := time.Parse(time.RFC3339, manifest.PublishedAt); err != nil {
		return fmt.Errorf("release manifest has an invalid publication timestamp")
	}
	if len(manifest.Artifacts) == 0 {
		return fmt.Errorf("release manifest contains no artifacts")
	}
	seen := map[string]bool{}
	for _, artifact := range manifest.Artifacts {
		key := artifact.Name
		if artifact.Name == "" || seen[key] {
			return fmt.Errorf("release manifest has a missing or duplicate artifact name %q", key)
		}
		seen[key] = true
		if !contains([]string{"windows", "linux", "macos", "portable"}, artifact.Platform) || !contains([]string{"x86", "x64", "arm64", "any"}, artifact.Architecture) {
			return fmt.Errorf("release artifact %q has an unsupported target", artifact.Name)
		}
		if err := validateImmutableHTTPS(artifact.URL); err != nil || !digestPattern.MatchString(artifact.SHA256) || artifact.SizeBytes < 1 || strings.TrimSpace(artifact.MinimumEnvironment) == "" {
			return fmt.Errorf("release artifact %q has invalid integrity metadata", artifact.Name)
		}
	}
	return nil
}

func (m *Manifest) Select(platform, architecture string) (Artifact, error) {
	for _, artifact := range m.Artifacts {
		if artifact.Platform == platform && (artifact.Architecture == architecture || artifact.Architecture == "any") {
			return artifact, nil
		}
	}
	return Artifact{}, fmt.Errorf("release %s has no artifact for %s/%s", m.Version, platform, architecture)
}

func (c *Client) DownloadVerified(artifact Artifact, destination string) error {
	if err := validateImmutableHTTPS(artifact.URL); err != nil {
		return err
	}
	data, err := c.download(artifact.URL, artifact.SizeBytes)
	if err != nil {
		return err
	}
	if int64(len(data)) != artifact.SizeBytes {
		return fmt.Errorf("artifact size mismatch: expected %d, received %d", artifact.SizeBytes, len(data))
	}
	digest := sha256.Sum256(data)
	if !strings.EqualFold(hex.EncodeToString(digest[:]), artifact.SHA256) {
		return fmt.Errorf("artifact SHA-256 mismatch")
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	temporary := destination + ".tmp"
	if err := os.WriteFile(temporary, data, 0o755); err != nil {
		return err
	}
	if err := os.Rename(temporary, destination); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	return nil
}

func (c *Client) download(address string, maximumBytes int64) ([]byte, error) {
	if err := validateHTTPS(address); err != nil {
		return nil, err
	}
	client := c.HTTP
	if client == nil {
		client = NewClient().HTTP
	}
	response, err := client.Get(address)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download returned HTTP %d", response.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, maximumBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > maximumBytes {
		return nil, fmt.Errorf("download exceeded declared size limit")
	}
	return data, nil
}

func validateHTTPS(value string) error {
	parsed, err := url.ParseRequestURI(value)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" || parsed.User != nil || parsed.Fragment != "" || strings.ContainsAny(value, "\r\n\x00") {
		return fmt.Errorf("immutable release URL must use HTTPS without credentials or fragments")
	}
	return nil
}

func validateImmutableHTTPS(value string) error {
	if err := validateHTTPS(value); err != nil {
		return err
	}
	lower := strings.ToLower(value)
	for _, marker := range []string{"/refs/heads/", "/raw/main/", "/raw/master/", "/archive/refs/heads/", "/default-branch/"} {
		if strings.Contains(lower, marker) {
			return fmt.Errorf("mutable default-branch release URL is prohibited")
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
