package repo

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInitCreatesRepoLayout(t *testing.T) {
	tmp := t.TempDir()

	if err := Init(tmp); err != nil {
		t.Fatalf("Init() error = %v", err)
	}

	repoDir := filepath.Join(tmp, DirName)
	expected := []string{
		repoDir,
		filepath.Join(repoDir, "objects"),
		filepath.Join(repoDir, "commits"),
		filepath.Join(repoDir, "refs"),
		filepath.Join(repoDir, "HEAD"),
		filepath.Join(repoDir, "refs", "main"),
	}

	for _, p := range expected {
		if _, err := os.Stat(p); err != nil {
			t.Fatalf("expected %s to exist: %v", p, err)
		}
	}
}
