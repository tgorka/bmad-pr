import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runAutoFix, runPreflight } from "./preflight.ts";
import type { PreflightResult, Runner, RunnerResult } from "./types.ts";

type Call = { cmd: string; args: readonly string[]; cwd: string | undefined };

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "bmad-pr-preflight-"));
  mkdirSync(join(tmp, ".git"), { recursive: true });
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

function stubRunner(
  responses: Record<string, ReadonlyArray<Partial<RunnerResult>>>,
): { runner: Runner; calls: Call[] } {
  const calls: Call[] = [];
  const cursor: Record<string, number> = {};
  const runner: Runner = async (cmd, args, opts) => {
    calls.push({ cmd, args, cwd: opts?.cwd });
    const full = `${cmd} ${args.join(" ")}`;
    const head2 = `${cmd} ${args.slice(0, 2).join(" ")}`;
    const head1 = `${cmd} ${args[0] ?? ""}`;
    const key =
      (responses[full] && full) ||
      (responses[head2] && head2) ||
      (responses[head1] && head1) ||
      cmd;
    const list = responses[key] ?? [];
    const i = cursor[key] ?? 0;
    cursor[key] = i + 1;
    const r = list[i] ?? {};
    return {
      stdout: r.stdout ?? "",
      stderr: r.stderr ?? "",
      exitCode: r.exitCode ?? 0,
    };
  };
  return { runner, calls };
}

const cleanResponses = (): Record<
  string,
  ReadonlyArray<Partial<RunnerResult>>
> => ({
  "git rev-parse --abbrev-ref": [{ exitCode: 0, stdout: "feat/x\n" }],
  "git rev-parse --git-dir": [{ exitCode: 0, stdout: ".git\n" }],
  "git status --porcelain": [{ exitCode: 0, stdout: "" }],
  "git rev-parse --abbrev-ref --symbolic-full-name @{u}": [
    { exitCode: 0, stdout: "origin/feat/x\n" },
  ],
  "git rev-list --count": [{ exitCode: 0, stdout: "0\n" }],
});

describe("runPreflight", () => {
  test("returns ok when all detectors pass on a clean repo", async () => {
    const { runner } = stubRunner(cleanResponses());
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(true);
  });

  test("CH1: detached HEAD → refuse with auto-fix hint", async () => {
    const responses = cleanResponses();
    responses["git rev-parse --abbrev-ref"] = [
      { exitCode: 0, stdout: "HEAD\n" },
    ];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CH1");
      expect(result.autoFixable).toBe(true);
      expect(result.hint).toBe(
        "detached HEAD. Try: bmad-pr --auto-fix to branch from current HEAD.",
      );
    }
  });

  test("CH2 mid-rebase (rebase-merge/) → refuse, NOT auto-fixable", async () => {
    mkdirSync(join(tmp, ".git", "rebase-merge"), { recursive: true });
    const { runner } = stubRunner(cleanResponses());
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CH2");
      expect(result.autoFixable).toBe(false);
      expect(result.hint).toContain("interactive rebase in progress");
      expect(result.hint).toContain("git rebase --continue");
    }
  });

  test("CH2 mid-rebase (rebase-apply/) → refuse", async () => {
    mkdirSync(join(tmp, ".git", "rebase-apply"), { recursive: true });
    const { runner } = stubRunner(cleanResponses());
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("CH2");
  });

  test("CH2 mid-merge (MERGE_HEAD) → refuse with merge hint", async () => {
    writeFileSync(join(tmp, ".git", "MERGE_HEAD"), "deadbeef\n");
    const { runner } = stubRunner(cleanResponses());
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CH2");
      expect(result.autoFixable).toBe(false);
      expect(result.hint).toContain("merge in progress");
      expect(result.hint).toContain("git merge --continue");
    }
  });

  test("CH3: dirty path outside _bmad-output/ → refuse with auto-fix hint", async () => {
    const responses = cleanResponses();
    responses["git status --porcelain"] = [
      { exitCode: 0, stdout: " M src/foo.ts\0" },
    ];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CH3");
      expect(result.autoFixable).toBe(true);
      expect(result.hint).toContain("unstaged changes outside _bmad-output/");
    }
  });

  test("CH3 tolerable: only _bmad-output/ paths dirty → ok", async () => {
    const responses = cleanResponses();
    responses["git status --porcelain"] = [
      { exitCode: 0, stdout: " M _bmad-output/stories/3.2.md\0" },
    ];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(true);
  });

  test("CH3: porcelain reports renames; both old and new paths under _bmad-output/ → ok", async () => {
    const responses = cleanResponses();
    // In `-z` output, a rename record is two NUL-separated fields:
    // "R  <new>\0<old>\0".
    responses["git status --porcelain"] = [
      {
        exitCode: 0,
        stdout: "R  _bmad-output/stories/3.2.md\0_bmad-output/stories/3.1.md\0",
      },
    ];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(true);
  });

  test("CH3: rename touching a non-BMAD path → refuse", async () => {
    const responses = cleanResponses();
    responses["git status --porcelain"] = [
      {
        exitCode: 0,
        stdout: "R  _bmad-output/stories/3.2.md\0src/old.ts\0",
      },
    ];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("CH3");
  });

  test("CH5: upstream ahead → refuse with auto-fix hint", async () => {
    const responses = cleanResponses();
    responses["git rev-list --count"] = [{ exitCode: 0, stdout: "3\n" }];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe("CH5");
      expect(result.autoFixable).toBe(true);
      expect(result.hint).toContain("remote has new commits ahead of local");
    }
  });

  test("CH5: no upstream configured → no-op (preflight passes)", async () => {
    const responses = cleanResponses();
    responses["git rev-parse --abbrev-ref --symbolic-full-name @{u}"] = [
      { exitCode: 128, stderr: "fatal: no upstream configured\n" },
    ];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(true);
  });

  test("first failure wins: CH1 + CH3 both present → CH1 returned", async () => {
    const responses = cleanResponses();
    responses["git rev-parse --abbrev-ref"] = [
      { exitCode: 0, stdout: "HEAD\n" },
    ];
    responses["git status --porcelain"] = [
      { exitCode: 0, stdout: " M src/foo.ts\0" },
    ];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("CH1");
  });

  test("CH3: path containing a literal newline does NOT escape the parser (high-severity quoting hole guard)", async () => {
    const responses = cleanResponses();
    // A real path with an embedded newline. With NUL framing, this is a
    // single record; the legacy `\n` parser would have split it apart and
    // potentially seen "_bmad-output/safe.md" on a second line, masking
    // the non-BMAD source.
    responses["git status --porcelain"] = [
      {
        exitCode: 0,
        stdout: " M src/weird\n_bmad-output/safe.md\0",
      },
    ];
    const { runner } = stubRunner(responses);
    const result = await runPreflight(runner, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("CH3");
  });

  test("runner cwd is forwarded for every detector call", async () => {
    const { runner, calls } = stubRunner(cleanResponses());
    await runPreflight(runner, { repoRoot: tmp });
    for (const c of calls) {
      expect(c.cwd).toBe(tmp);
    }
  });
});

describe("runAutoFix", () => {
  test("CH1: invokes `git switch -c bmad-pr/<sha>-<ts>`", async () => {
    const responses: Record<string, ReadonlyArray<Partial<RunnerResult>>> = {
      "git rev-parse --short=7 HEAD": [{ exitCode: 0, stdout: "abc1234\n" }],
      "git switch": [{ exitCode: 0 }],
    };
    const { runner, calls } = stubRunner(responses);
    const failure: PreflightResult = {
      ok: false,
      code: "CH1",
      hint: "x",
      autoFixable: true,
    };
    const result = await runAutoFix(runner, failure, { repoRoot: tmp });
    expect(result.ok).toBe(true);
    const switchCall = calls.find(
      (c) => c.cmd === "git" && c.args[0] === "switch",
    );
    expect(switchCall).toBeDefined();
    expect(switchCall?.args[1]).toBe("-c");
    expect(switchCall?.args[2] ?? "").toMatch(/^bmad-pr\/[0-9a-f]{7,}-\d+$/);
  });

  test("CH1: refuse if `git switch -c` exits non-zero", async () => {
    const responses: Record<string, ReadonlyArray<Partial<RunnerResult>>> = {
      "git rev-parse --short=7 HEAD": [{ exitCode: 0, stdout: "abc1234\n" }],
      "git switch": [{ exitCode: 1, stderr: "branch already exists" }],
    };
    const { runner } = stubRunner(responses);
    const failure: PreflightResult = {
      ok: false,
      code: "CH1",
      hint: "x",
      autoFixable: true,
    };
    const result = await runAutoFix(runner, failure, { repoRoot: tmp });
    expect(result.ok).toBe(false);
  });

  test("CH3: invokes `git add _bmad-output/` exactly once", async () => {
    const responses: Record<string, ReadonlyArray<Partial<RunnerResult>>> = {
      "git add": [{ exitCode: 0 }],
    };
    const { runner, calls } = stubRunner(responses);
    const failure: PreflightResult = {
      ok: false,
      code: "CH3",
      hint: "x",
      autoFixable: true,
    };
    await runAutoFix(runner, failure, { repoRoot: tmp });
    const addCalls = calls.filter(
      (c) => c.cmd === "git" && c.args[0] === "add",
    );
    expect(addCalls).toHaveLength(1);
    expect(addCalls[0]?.args).toEqual(["add", "_bmad-output/"]);
  });

  test("CH5: invokes `git pull --rebase`; ok on clean exit", async () => {
    const responses: Record<string, ReadonlyArray<Partial<RunnerResult>>> = {
      "git pull --rebase": [{ exitCode: 0 }],
    };
    const { runner, calls } = stubRunner(responses);
    const failure: PreflightResult = {
      ok: false,
      code: "CH5",
      hint: "x",
      autoFixable: true,
    };
    const result = await runAutoFix(runner, failure, { repoRoot: tmp });
    expect(result.ok).toBe(true);
    const pullCall = calls.find((c) => c.cmd === "git" && c.args[0] === "pull");
    expect(pullCall?.args).toEqual(["pull", "--rebase"]);
  });

  test("CH5: on rebase conflict, run `git rebase --abort` AND refuse", async () => {
    const responses: Record<string, ReadonlyArray<Partial<RunnerResult>>> = {
      "git pull --rebase": [{ exitCode: 1, stderr: "CONFLICT" }],
      "git rebase --abort": [{ exitCode: 0 }],
    };
    const { runner, calls } = stubRunner(responses);
    const failure: PreflightResult = {
      ok: false,
      code: "CH5",
      hint: "x",
      autoFixable: true,
    };
    const result = await runAutoFix(runner, failure, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.hint).toContain("aborted");
    }
    const abortCall = calls.find(
      (c) =>
        c.cmd === "git" && c.args[0] === "rebase" && c.args[1] === "--abort",
    );
    expect(abortCall).toBeDefined();
  });

  test("CH2: rejected — never auto-fixable", async () => {
    const { runner, calls } = stubRunner({});
    const failure: PreflightResult = {
      ok: false,
      code: "CH2",
      hint: "x",
      autoFixable: false,
    };
    const result = await runAutoFix(runner, failure, { repoRoot: tmp });
    expect(result.ok).toBe(false);
    expect(calls).toHaveLength(0);
  });
});
