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
});
