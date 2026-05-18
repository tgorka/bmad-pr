import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Runner, RunnerResult } from "../pr/types.ts";
import { run } from "./bmad-pr.ts";

type Call = {
  cmd: string;
  args: readonly string[];
  cwd: string | undefined;
};

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "bmad-pr-cli-"));
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

function harness(
  responses: Record<string, ReadonlyArray<Partial<RunnerResult>>>,
): { runner: Runner; calls: Call[]; chunks: string[] } {
  const calls: Call[] = [];
  const cursor: Record<string, number> = {};
  const runner: Runner = async (cmd, args, opts) => {
    calls.push({ cmd, args, cwd: opts?.cwd });
    const key = matchKey(cmd, args, responses);
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
  return { runner, calls, chunks: [] };
}

function matchKey(
  cmd: string,
  args: readonly string[],
  responses: Record<string, unknown>,
): string {
  const full = `${cmd} ${args.join(" ")}`;
  if (responses[full]) return full;
  const head2 = `${cmd} ${args.slice(0, 2).join(" ")}`;
  if (responses[head2]) return head2;
  const head1 = `${cmd} ${args[0] ?? ""}`;
  if (responses[head1]) return head1;
  return cmd;
}

const happyResponses = (
  toplevel: string,
): Record<string, ReadonlyArray<Partial<RunnerResult>>> => ({
  "gh --version": [{ exitCode: 0, stdout: "gh version 2.40.0\n" }],
  "git rev-parse --show-toplevel": [{ exitCode: 0, stdout: `${toplevel}\n` }],
  "git rev-parse --abbrev-ref": [{ exitCode: 0, stdout: "feat/x\n" }],
  "git push": [{ exitCode: 0 }],
  "gh pr create": [{ exitCode: 0, stdout: "https://github.com/o/r/pull/42\n" }],
  "gh pr edit": [{ exitCode: 0 }],
});

const stderrOf = (chunks: string[]) => chunks.join("");

describe("run --help", () => {
  test("prints flag list to stdout and exits 0", async () => {
    const stdout: string[] = [];
    const stderr: string[] = [];
    const result = await run(["--help"], {
      runner: harness({}).runner,
      cwd: tmp,
      stdoutSink: (s) => stdout.push(s),
      stderrSink: (s) => stderr.push(s),
    });
    expect(result).toBe(0);
    expect(stdout.join("")).toContain("--story");
    expect(stdout.join("")).toContain("--amend");
  });
});

describe("run open path", () => {
  test("opens a new PR and writes a ledger entry", async () => {
    const { runner, calls } = harness(happyResponses(tmp));
    const stdout: string[] = [];
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--run-id", "R1"],
      {
        runner,
        cwd: tmp,
        stdoutSink: (s) => stdout.push(s),
        stderrSink: (s) => stderr.push(s),
        now: () => new Date("2026-05-17T14:22:03Z"),
      },
    );
    expect(code).toBe(0);
    expect(stdout.join("")).toContain("https://github.com/o/r/pull/42");
    const pushCall = calls.find((c) => c.cmd === "git" && c.args[0] === "push");
    expect(pushCall).toBeDefined();
    const createCall = calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "create",
    );
    expect(createCall).toBeDefined();
    expect(createCall?.args).toContain("--draft");
    const written = readFileSync(
      join(tmp, "_bmad-output/stories/3.2.md"),
      "utf8",
    );
    expect(written).toContain("phase: dev-story");
    expect(written).toContain("status: open");
    expect(written).toContain("runId: R1");
    expect(written).toContain("openedAt: 2026-05-17T14:22:03Z");
    expect(written).toContain("lastAmendedAt: 2026-05-17T14:22:03Z");
    // Every driver-routed git/gh call should have run inside the repo root.
    const driverCalls = calls.filter(
      (c) =>
        (c.cmd === "gh" && c.args[0] !== "--version") ||
        (c.cmd === "git" && c.args[0] === "push") ||
        (c.cmd === "git" && c.args[0] === "rev-parse"),
    );
    for (const c of driverCalls) {
      expect(c.cwd).toBe(tmp);
    }
  });
});

describe("run auto-amend path", () => {
  test("amends existing open entry on the second invocation", async () => {
    const responses1 = happyResponses(tmp);
    const responses2 = happyResponses(tmp);
    const h1 = harness(responses1);
    const code1 = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: h1.runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: () => {},
      now: () => new Date("2026-05-17T14:00:00Z"),
    });
    expect(code1).toBe(0);
    const h2 = harness(responses2);
    const code2 = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: h2.runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: () => {},
      now: () => new Date("2026-05-17T15:00:00Z"),
    });
    expect(code2).toBe(0);
    const editCall = h2.calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "edit",
    );
    expect(editCall).toBeDefined();
    expect(editCall?.args[2]).toBe("42");
    const createAttempt = h2.calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "create",
    );
    expect(createAttempt).toBeUndefined();
    const written = readFileSync(
      join(tmp, "_bmad-output/stories/3.2.md"),
      "utf8",
    );
    expect(written).toContain("openedAt: 2026-05-17T14:00:00Z");
    expect(written).toContain("lastAmendedAt: 2026-05-17T15:00:00Z");
  });

  test("preserves original runId on amend (ignores new --run-id)", async () => {
    const responses1 = happyResponses(tmp);
    const h1 = harness(responses1);
    await run(
      ["--story", "3.2", "--phase", "dev-story", "--run-id", "R-ORIGINAL"],
      {
        runner: h1.runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: () => {},
        now: () => new Date("2026-05-17T14:00:00Z"),
      },
    );
    const responses2 = happyResponses(tmp);
    const h2 = harness(responses2);
    await run(["--story", "3.2", "--phase", "dev-story", "--run-id", "R-NEW"], {
      runner: h2.runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: () => {},
      now: () => new Date("2026-05-17T15:00:00Z"),
    });
    const editCall = h2.calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "edit",
    );
    const bodyArg = editCall?.args[4] ?? "";
    expect(bodyArg).toContain("BMAD-Run-Id: R-ORIGINAL");
    expect(bodyArg).not.toContain("BMAD-Run-Id: R-NEW");
    const written = readFileSync(
      join(tmp, "_bmad-output/stories/3.2.md"),
      "utf8",
    );
    expect(written).toContain("runId: R-ORIGINAL");
    expect(written).not.toContain("runId: R-NEW");
  });
});

describe("run --amend with no match", () => {
  test("refuses with exit 2", async () => {
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--amend"],
      {
        runner: harness(happyResponses(tmp)).runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: (s) => stderr.push(s),
        now: () => new Date(),
      },
    );
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("requires an existing PR");
  });
});

describe("run refusals", () => {
  test("on trunk branch", async () => {
    const responses = happyResponses(tmp);
    responses["git rev-parse --abbrev-ref"] = [
      { exitCode: 0, stdout: "main\n" },
    ];
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(responses).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("on trunk branch");
  });

  test("missing gh", async () => {
    const responses = happyResponses(tmp);
    responses["gh --version"] = [
      { exitCode: 127, stderr: "command not found" },
    ];
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(responses).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("'gh' CLI not on PATH");
  });

  test("--trunk-branch override refuses on the named branch", async () => {
    const responses = happyResponses(tmp);
    responses["git rev-parse --abbrev-ref"] = [
      { exitCode: 0, stdout: "develop\n" },
    ];
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--trunk-branch", "develop"],
      {
        runner: harness(responses).runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: (s) => stderr.push(s),
        now: () => new Date(),
      },
    );
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("on trunk branch 'develop'");
  });

  test("flag value starting with -- is rejected", async () => {
    const stderr: string[] = [];
    const code = await run(["--story", "--phase", "dev-story"], {
      runner: harness(happyResponses(tmp)).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("--story requires a value");
  });

  test("malformed --story", async () => {
    const stderr: string[] = [];
    const code = await run(["--story", "foo", "--phase", "dev-story"], {
      runner: harness(happyResponses(tmp)).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("<epic>.<story>");
  });

  test("git rev-parse failure surfaces the real stderr (not a generic message)", async () => {
    const responses = happyResponses(tmp);
    responses["git rev-parse --show-toplevel"] = [
      {
        exitCode: 128,
        stderr:
          "fatal: not a git repository (or any of the parent directories): .git\n",
      },
    ];
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(responses).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    const combined = stderrOf(stderr);
    expect(combined).toContain("git rev-parse --show-toplevel failed");
    expect(combined).toContain("fatal: not a git repository");
  });

  test("git rev-parse failure with empty stderr falls back to exit-code detail", async () => {
    const responses = happyResponses(tmp);
    responses["git rev-parse --show-toplevel"] = [
      { exitCode: 130, stderr: "" },
    ];
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(responses).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("exit 130");
  });

  test("unparseable stored PR URL refuses (exit 2, not exit 1)", async () => {
    const fs = await import("node:fs");
    fs.mkdirSync(join(tmp, "_bmad-output/stories"), { recursive: true });
    writeFileSync(
      join(tmp, "_bmad-output/stories/3.2.md"),
      "---\nepic: 3\nstory: 2\nprs:\n  - url: not-a-valid-url\n    phase: dev-story\n    status: open\n    openedAt: 2026-05-17T10:00:00Z\n    lastAmendedAt: 2026-05-17T10:00:00Z\n---\n",
    );
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(happyResponses(tmp)).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("unparseable");
  });

  test("unparseable stored PR URL refuses under --dry-run too", async () => {
    const fs = await import("node:fs");
    fs.mkdirSync(join(tmp, "_bmad-output/stories"), { recursive: true });
    writeFileSync(
      join(tmp, "_bmad-output/stories/3.2.md"),
      "---\nepic: 3\nstory: 2\nprs:\n  - url: also-broken\n    phase: dev-story\n    status: open\n    openedAt: 2026-05-17T10:00:00Z\n    lastAmendedAt: 2026-05-17T10:00:00Z\n---\n",
    );
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--dry-run"],
      {
        runner: harness(happyResponses(tmp)).runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: (s) => stderr.push(s),
        now: () => new Date(),
      },
    );
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("unparseable");
  });

  test("malformed ledger entry", async () => {
    const storyPath = join(tmp, "_bmad-output/stories/3.2.md");
    const fs = await import("node:fs");
    fs.mkdirSync(join(tmp, "_bmad-output/stories"), { recursive: true });
    writeFileSync(
      storyPath,
      "---\nprs:\n  - phase: dev-story\n    status: open\n    openedAt: x\n    lastAmendedAt: x\n---\n",
    );
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(happyResponses(tmp)).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("missing 'url'");
  });
});

describe("run preflight (G2)", () => {
  test("CH1 detached HEAD without --auto-fix refuses with exit 2", async () => {
    const responses = happyResponses(tmp);
    responses["git rev-parse --abbrev-ref"] = [
      // CLI's detectBranch — also returns HEAD when detached
      { exitCode: 0, stdout: "HEAD\n" },
      // Preflight CH1 detector — same condition
      { exitCode: 0, stdout: "HEAD\n" },
    ];
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(responses).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("detached HEAD");
    expect(stderrOf(stderr)).toContain("--auto-fix");
  });

  test("CH1 with --auto-fix runs `git switch -c bmad-pr/<sha>-<ts>` and proceeds", async () => {
    const responses = happyResponses(tmp);
    // The CLI's detectBranch fires before preflight, so the call sequence is:
    // 1) detectBranch → returns "HEAD" (detached)
    // 2) preflight CH1 first probe → returns "HEAD" → triggers auto-fix
    // 3) preflight CH1 second probe (after `git switch -c …`) → now on a branch
    responses["git rev-parse --abbrev-ref"] = [
      { exitCode: 0, stdout: "HEAD\n" },
      { exitCode: 0, stdout: "HEAD\n" },
      { exitCode: 0, stdout: "feat/x\n" },
    ];
    responses["git rev-parse --short=7 HEAD"] = [
      { exitCode: 0, stdout: "abc1234\n" },
    ];
    responses["git switch"] = [{ exitCode: 0 }];
    const { runner, calls } = harness(responses);
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--auto-fix"],
      {
        runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: () => {},
        now: () => new Date("2026-05-17T14:22:03Z"),
      },
    );
    expect(code).toBe(0);
    const switchCall = calls.find(
      (c) => c.cmd === "git" && c.args[0] === "switch",
    );
    expect(switchCall).toBeDefined();
    expect(switchCall?.args[2] ?? "").toMatch(/^bmad-pr\/[0-9a-f]{7,}-\d+$/);
  });

  test("CH2 mid-rebase refuses even with --auto-fix", async () => {
    const fs = await import("node:fs");
    fs.mkdirSync(join(tmp, ".git", "rebase-merge"), { recursive: true });
    const responses = happyResponses(tmp);
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--auto-fix"],
      {
        runner: harness(responses).runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: (s) => stderr.push(s),
        now: () => new Date(),
      },
    );
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("interactive rebase in progress");
  });

  test("CH3 dirty tree without --auto-fix refuses", async () => {
    const responses = happyResponses(tmp);
    responses["git status --porcelain"] = [
      { exitCode: 0, stdout: " M src/foo.ts\0" },
    ];
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(responses).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain(
      "unstaged changes outside _bmad-output/",
    );
  });

  test("CH3 with --auto-fix and clean residue runs `git add _bmad-output/` and proceeds", async () => {
    const responses = happyResponses(tmp);
    responses["git status --porcelain"] = [
      {
        exitCode: 0,
        stdout: " M _bmad-output/stories/3.2.md\0 M src/foo.ts\0",
      }, // first: dirty
      { exitCode: 0, stdout: "" }, // after `git add _bmad-output/`: clean (test fixture)
    ];
    responses["git add"] = [{ exitCode: 0 }];
    const { runner, calls } = harness(responses);
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--auto-fix"],
      {
        runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: () => {},
        now: () => new Date("2026-05-17T14:22:03Z"),
      },
    );
    expect(code).toBe(0);
    const addCalls = calls.filter(
      (c) => c.cmd === "git" && c.args[0] === "add",
    );
    expect(addCalls).toHaveLength(1);
    expect(addCalls[0]?.args).toEqual(["add", "_bmad-output/"]);
  });

  test("CH3 with --auto-fix but non-BMAD residue refuses", async () => {
    const responses = happyResponses(tmp);
    responses["git status --porcelain"] = [
      { exitCode: 0, stdout: " M src/foo.ts\0" }, // first: dirty
      { exitCode: 0, stdout: " M src/foo.ts\0" }, // after add: still dirty
    ];
    responses["git add"] = [{ exitCode: 0 }];
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--auto-fix"],
      {
        runner: harness(responses).runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: (s) => stderr.push(s),
        now: () => new Date(),
      },
    );
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("CH3 auto-fix could not clean tree");
  });

  test("CH5 upstream ahead + --auto-fix conflict: rebase --abort runs and no push happens", async () => {
    const responses = happyResponses(tmp);
    responses["git rev-list --count"] = [
      { exitCode: 0, stdout: "3\n" }, // first: ahead
    ];
    responses["git pull --rebase"] = [
      { exitCode: 1, stderr: "CONFLICT (content): merge conflict" },
    ];
    responses["git rebase --abort"] = [{ exitCode: 0 }];
    const { runner, calls } = harness(responses);
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--auto-fix"],
      {
        runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: (s) => stderr.push(s),
        now: () => new Date(),
      },
    );
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("aborted");
    const abortCall = calls.find(
      (c) =>
        c.cmd === "git" && c.args[0] === "rebase" && c.args[1] === "--abort",
    );
    expect(abortCall).toBeDefined();
    // CRITICAL: never push or create after a CH5 conflict.
    const pushCall = calls.find((c) => c.cmd === "git" && c.args[0] === "push");
    expect(pushCall).toBeUndefined();
    const createCall = calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "create",
    );
    expect(createCall).toBeUndefined();
  });
});

describe("run --dry-run", () => {
  test("prints would-run plan, makes no side-effecting calls", async () => {
    const { runner, calls } = harness(happyResponses(tmp));
    const stdout: string[] = [];
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--dry-run"],
      {
        runner,
        cwd: tmp,
        stdoutSink: (s) => stdout.push(s),
        stderrSink: (s) => stderr.push(s),
        now: () => new Date("2026-05-17T14:22:03Z"),
      },
    );
    expect(code).toBe(0);
    expect(stdout.join("")).toContain("preflight: ok");
    expect(stdout.join("")).toContain("would run: git push");
    expect(stdout.join("")).toContain("would run: gh pr create");
    expect(stdout.join("")).toContain("ledger diff");
    const sideEffectCalls = calls.filter(
      (c) =>
        (c.cmd === "git" && c.args[0] === "push") ||
        (c.cmd === "gh" && (c.args[1] === "create" || c.args[1] === "edit")),
    );
    expect(sideEffectCalls).toHaveLength(0);
    // No story file should be written.
    const fs = await import("node:fs");
    expect(fs.existsSync(join(tmp, "_bmad-output/stories/3.2.md"))).toBe(false);
  });
});
