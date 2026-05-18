package repo

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const DirName = ".pino"

func Init(root string) error {
	repoDir := filepath.Join(root, DirName)
	if _, err := os.Stat(repoDir); err == nil {
		return fmt.Errorf("pino repository already exists at %s", repoDir)
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("stat repo: %w", err)
	}

	dirs := []string{
		repoDir,
		filepath.Join(repoDir, "objects"),
		filepath.Join(repoDir, "commits"),
		filepath.Join(repoDir, "refs"),
	}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("create %s: %w", dir, err)
		}
	}

	headPath := filepath.Join(repoDir, "HEAD")
	if err := os.WriteFile(headPath, []byte("refs/main\n"), 0o644); err != nil {
		return fmt.Errorf("write HEAD: %w", err)
	}

	mainRef := filepath.Join(repoDir, "refs", "main")
	if err := os.WriteFile(mainRef, nil, 0o644); err != nil {
		return fmt.Errorf("write main ref: %w", err)
	}

	fmt.Printf("Initialized empty Pino repository in %s\n", repoDir)
	return nil
}
