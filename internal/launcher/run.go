// Package launcher materializes the embedded Tcl/Tk app and starts it.
package launcher

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/anafalanx/pino"
)

const appScript = "tcl/app.tcl"

func Run(args []string) error {
	if runtime.GOOS != "windows" {
		return errors.New("embedded Tcl/Tk runtime is currently available for Windows only")
	}

	root, err := materializeEmbeddedApp()
	if err != nil {
		return err
	}

	workspace := os.Getenv("PINO_WORKSPACE")
	if workspace == "" {
		var err error
		workspace, err = os.Getwd()
		if err != nil {
			return fmt.Errorf("get workspace: %w", err)
		}
	}
	workspace, err = filepath.Abs(workspace)
	if err != nil {
		return fmt.Errorf("resolve workspace: %w", err)
	}

	runtimeBin := filepath.Join(root, "tcltk", "bin")
	exeName := "wish90.exe"
	if hasArg(args, "--check") || hasArg(args, "--repo-check") {
		exeName = "tclsh90.exe"
	}

	launcherPath := filepath.Join(runtimeBin, exeName)
	if _, err := os.Stat(launcherPath); err != nil {
		return fmt.Errorf("find embedded Tcl/Tk launcher: %w", err)
	}

	cmdArgs := append([]string{filepath.Join(root, filepath.FromSlash(appScript))}, args...)
	cmd := exec.Command(launcherPath, cmdArgs...)
	cmd.Dir = workspace
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = launcherEnv(os.Environ(), root, runtimeBin, workspace)

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("run embedded Tcl app: %w", err)
	}
	return nil
}

func hasArg(args []string, name string) bool {
	for _, arg := range args {
		if arg == name {
			return true
		}
	}
	return false
}

func launcherEnv(env []string, root string, runtimeBin string, workspace string) []string {
	env = setEnv(env, "PINO_ROOT", root)
	env = setEnv(env, "PINO_TCLTK", filepath.Join(root, "tcltk"))
	env = setEnv(env, "PINO_WORKSPACE", workspace)
	env = setEnv(env, "PATH", runtimeBin+string(os.PathListSeparator)+getEnv(env, "PATH"))
	return env
}

func getEnv(env []string, key string) string {
	prefix := key + "="
	for _, entry := range env {
		if len(entry) >= len(prefix) && strings.EqualFold(entry[:len(prefix)], prefix) {
			return entry[len(prefix):]
		}
	}
	return ""
}

func setEnv(env []string, key string, value string) []string {
	prefix := key + "="
	entry := prefix + value
	for i, existing := range env {
		if len(existing) >= len(prefix) && strings.EqualFold(existing[:len(prefix)], prefix) {
			env[i] = entry
			return env
		}
	}
	return append(env, entry)
}

func materializeEmbeddedApp() (string, error) {
	digest, err := embeddedDigest()
	if err != nil {
		return "", err
	}

	cacheRoot, err := os.UserCacheDir()
	if err != nil || cacheRoot == "" {
		cacheRoot = os.TempDir()
	}

	dest := filepath.Join(cacheRoot, "pino", "embedded", digest)
	marker := filepath.Join(dest, ".complete")
	if data, err := os.ReadFile(marker); err == nil && strings.TrimSpace(string(data)) == digest {
		return dest, nil
	}

	if err := os.RemoveAll(dest); err != nil {
		return "", fmt.Errorf("clear stale embedded app: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return "", fmt.Errorf("create embedded app cache: %w", err)
	}
	if err := copyEmbeddedFiles(dest); err != nil {
		_ = os.RemoveAll(dest)
		return "", err
	}
	if err := os.WriteFile(filepath.Join(dest, ".complete"), []byte(digest+"\n"), 0o644); err != nil {
		_ = os.RemoveAll(dest)
		return "", fmt.Errorf("write embedded app marker: %w", err)
	}

	return dest, nil
}

func embeddedDigest() (string, error) {
	hash := sha256.New()
	if err := fs.WalkDir(pino.Assets, ".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		_, _ = hash.Write([]byte(path))
		if entry.IsDir() {
			_, _ = hash.Write([]byte{0, 'd'})
			return nil
		}
		_, _ = hash.Write([]byte{0, 'f'})
		file, err := pino.Assets.Open(path)
		if err != nil {
			return err
		}
		_, copyErr := io.Copy(hash, file)
		closeErr := file.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
		return nil
	}); err != nil {
		return "", fmt.Errorf("hash embedded app: %w", err)
	}

	return hex.EncodeToString(hash.Sum(nil))[:16], nil
}

func copyEmbeddedFiles(dest string) error {
	return fs.WalkDir(pino.Assets, ".", func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if path == "." {
			return nil
		}

		outPath := filepath.Join(dest, filepath.FromSlash(path))
		if entry.IsDir() {
			if err := os.MkdirAll(outPath, 0o755); err != nil {
				return fmt.Errorf("create embedded directory %s: %w", path, err)
			}
			return nil
		}

		data, err := pino.Assets.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read embedded file %s: %w", path, err)
		}
		if err := os.MkdirAll(filepath.Dir(outPath), 0o755); err != nil {
			return fmt.Errorf("create embedded file directory %s: %w", path, err)
		}
		if err := os.WriteFile(outPath, data, 0o644); err != nil {
			return fmt.Errorf("write embedded file %s: %w", path, err)
		}
		return nil
	})
}
