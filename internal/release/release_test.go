package release

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestVerifiedImmutableDownload(t *testing.T) {
	payload := []byte("immutable cowebs artifact")
	digest := sha256.Sum256(payload)
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		_, _ = writer.Write(payload)
	}))
	defer server.Close()
	client := &Client{HTTP: server.Client()}
	artifact := Artifact{Name: "cowebs", Platform: "linux", Architecture: "x64", URL: server.URL + "/cowebs", SHA256: hex.EncodeToString(digest[:]), SizeBytes: int64(len(payload)), MinimumEnvironment: "Ubuntu 24.04 or Fedora 43"}
	destination := filepath.Join(t.TempDir(), "cowebs")
	if err := client.DownloadVerified(artifact, destination); err != nil {
		t.Fatal(err)
	}
	if actual, err := os.ReadFile(destination); err != nil || string(actual) != string(payload) {
		t.Fatalf("downloaded artifact mismatch: %q %v", actual, err)
	}
	artifact.SHA256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	if err := client.DownloadVerified(artifact, destination); err == nil {
		t.Fatal("expected digest mismatch")
	}
}

func TestManifestValidation(t *testing.T) {
	manifest := &Manifest{SchemaVersion: 1, Version: "6.3.0", SourceCommit: "0123456789012345678901234567890123456789", PublishedAt: time.Now().UTC().Format(time.RFC3339), Artifacts: []Artifact{{Name: "cowebs", Platform: "linux", Architecture: "x64", URL: "https://example.com/cowebs", SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 1, MinimumEnvironment: "Ubuntu 24.04 or Fedora 43"}}}
	if err := ValidateManifest(manifest); err != nil {
		t.Fatal(err)
	}
	manifest.Artifacts[0].URL = "https://main.example.com/default-branch/cowebs"
	if err := ValidateManifest(manifest); err == nil {
		t.Fatal("expected mutable default-branch URL rejection")
	}
	manifest.Artifacts[0].URL = "http://example.com/cowebs"
	if err := ValidateManifest(manifest); err == nil {
		t.Fatal("expected non-HTTPS rejection")
	}
}
