import { describe, expect, test } from "bun:test";
import { runCommand } from "./runner.ts";

describe("runCommand", () => {
  test("captures stdout, stderr, and exit code from a real command", async () => {
    const result = await runCommand("git", ["--version"]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toMatch(/^git version /);
    expect(typeof result.stderr).toBe("string");
  });

  test("returns the non-zero exit code without throwing", async () => {
    const result = await runCommand("git", [
      "rev-parse",
      "--verify",
      "definitely-not-a-ref",
    ]);
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr.length).toBeGreaterThan(0);
  });

  test("maps ENOENT spawn failure to exit code 127 (absolute non-existent path)", async () => {
    // Use an absolute path so PATH lookup is irrelevant — always ENOENT.
    const result = await runCommand("/var/empty/no-such-binary", []);
    expect(result.exitCode).toBe(127);
    expect(result.stderr.length).toBeGreaterThan(0);
  });

  test("nonexistent cwd reports cwd error (exit 1), not 'binary not found'", async () => {
    const result = await runCommand("git", ["--version"], {
      cwd: "/var/empty/definitely-not-a-real-dir-12345",
    });
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("cwd does not exist");
    // Critically: NOT 127, so detectGhOnPath wouldn't misclassify this.
    expect(result.exitCode).not.toBe(127);
  });

  test("cwd that is a file (not a directory) is rejected with exit 1", async () => {
    const { mkdtempSync, writeFileSync, rmSync } = await import("node:fs");
    const { tmpdir } = await import("node:os");
    const { join } = await import("node:path");
    const tmp = mkdtempSync(join(tmpdir(), "bmad-pr-runner-"));
    const filePath = join(tmp, "notadir");
    writeFileSync(filePath, "");
    try {
      const result = await runCommand("git", ["--version"], { cwd: filePath });
      expect(result.exitCode).toBe(1);
      expect(result.stderr).toContain("not a directory");
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});
