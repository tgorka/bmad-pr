import { existsSync, statSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import type { PreflightResult, Runner } from "./types.ts";

export type PreflightOpts = { repoRoot: string };

export async function runPreflight(
  runner: Runner,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  const ch1 = await detectCH1(runner, opts);
  if (!ch1.ok) return ch1;
  const ch2 = await detectCH2(runner, opts);
  if (!ch2.ok) return ch2;
  const ch3 = await detectCH3(runner, opts);
  if (!ch3.ok) return ch3;
  const ch5 = await detectCH5(runner, opts);
  if (!ch5.ok) return ch5;
  return { ok: true };
}

// Resolve the actual gitdir for this repo — handles worktrees, where the
// per-worktree gitdir is NOT `<repoRoot>/.git` but a sibling under
// `<commondir>/worktrees/<name>/`.
async function resolveGitDir(
  runner: Runner,
  opts: PreflightOpts,
): Promise<string> {
  const r = await runner("git", ["rev-parse", "--git-dir"], {
    cwd: opts.repoRoot,
  });
  const raw = r.exitCode === 0 ? r.stdout.trim() : "";
  if (raw === "") return join(opts.repoRoot, ".git");
  return isAbsolute(raw) ? raw : join(opts.repoRoot, raw);
}

async function detectCH1(
  runner: Runner,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  const r = await runner("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
    cwd: opts.repoRoot,
  });
  if (r.exitCode !== 0) return { ok: true };
  if (r.stdout.trim() === "HEAD") {
    return {
      ok: false,
      code: "CH1",
      hint: "detached HEAD. Try: bmad-pr --auto-fix to branch from current HEAD.",
      autoFixable: true,
    };
  }
  return { ok: true };
}

async function detectCH2(
  runner: Runner,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  const gitDir = await resolveGitDir(runner, opts);
  if (!existsSync(gitDir) || !statSync(gitDir).isDirectory()) {
    // Treat unresolvable git-dir as "no rebase/merge in progress" — CH1/CH5
    // will have already failed if we're not in a repo.
    return { ok: true };
  }
  if (
    existsSync(join(gitDir, "rebase-merge")) ||
    existsSync(join(gitDir, "rebase-apply"))
  ) {
    return {
      ok: false,
      code: "CH2",
      hint: "interactive rebase in progress. Run: git rebase --continue (or --abort).",
      autoFixable: false,
    };
  }
  if (existsSync(join(gitDir, "MERGE_HEAD"))) {
    return {
      ok: false,
      code: "CH2",
      hint: "merge in progress. Run: git merge --continue (or --abort).",
      autoFixable: false,
    };
  }
  return { ok: true };
}

async function detectCH3(
  runner: Runner,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  // Use NUL-delimited output so filenames with spaces, newlines, quotes, or
  // other shell metacharacters cannot fool the parser. (Plain `--porcelain`
  // C-quotes such paths; that quoting is not safely reversible with a regex.)
  const r = await runner("git", ["status", "--porcelain", "-z"], {
    cwd: opts.repoRoot,
  });
  if (r.exitCode !== 0) return { ok: true };
  for (const p of parsePorcelainZ(r.stdout)) {
    if (!p.startsWith("_bmad-output/")) {
      return {
        ok: false,
        code: "CH3",
        hint: "unstaged changes outside _bmad-output/. Try: bmad-pr --auto-fix to stage only _bmad-output/ paths.",
        autoFixable: true,
      };
    }
  }
  return { ok: true };
}

// Walk porcelain v1 -z output and yield every path (both sides of a rename
// or copy). Each record is "XY <space> PATH \0", and rename/copy records are
// followed by "ORIG_PATH \0" (the source path on its own).
function parsePorcelainZ(stream: string): string[] {
  const parts = stream.split("\0");
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const rec = parts[i];
    if (!rec || rec.length < 4) continue;
    const xy = rec.slice(0, 2);
    const path = rec.slice(3);
    out.push(path);
    if (xy[0] === "R" || xy[0] === "C") {
      const source = parts[++i];
      if (source !== undefined && source.length > 0) out.push(source);
    }
  }
  return out;
}

async function detectCH5(
  runner: Runner,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  const up = await runner(
    "git",
    ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
    { cwd: opts.repoRoot },
  );
  if (up.exitCode !== 0) return { ok: true }; // no upstream configured
  const count = await runner("git", ["rev-list", "--count", "HEAD..@{u}"], {
    cwd: opts.repoRoot,
  });
  if (count.exitCode !== 0) return { ok: true };
  const ahead = Number.parseInt(count.stdout.trim(), 10);
  if (Number.isFinite(ahead) && ahead > 0) {
    return {
      ok: false,
      code: "CH5",
      hint: "remote has new commits ahead of local. Try: bmad-pr --auto-fix to rebase first.",
      autoFixable: true,
    };
  }
  return { ok: true };
}

export async function runAutoFix(
  runner: Runner,
  failure: Exclude<PreflightResult, { ok: true }>,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  if (!failure.autoFixable) {
    return failure;
  }
  switch (failure.code) {
    case "CH1":
      return autoFixCH1(runner, opts);
    case "CH3":
      return autoFixCH3(runner, opts);
    case "CH5":
      return autoFixCH5(runner, opts);
    default:
      return failure;
  }
}

async function autoFixCH1(
  runner: Runner,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  const sha = await runner("git", ["rev-parse", "--short=7", "HEAD"], {
    cwd: opts.repoRoot,
  });
  if (sha.exitCode !== 0) {
    return {
      ok: false,
      code: "CH1",
      hint: `CH1 auto-fix failed: could not resolve HEAD short-sha: ${sha.stderr.trim()}`,
      autoFixable: false,
    };
  }
  const branch = `bmad-pr/${sha.stdout.trim()}-${Math.floor(Date.now() / 1000)}`;
  const r = await runner("git", ["switch", "-c", branch], {
    cwd: opts.repoRoot,
  });
  if (r.exitCode !== 0) {
    return {
      ok: false,
      code: "CH1",
      hint: `CH1 auto-fix failed: ${r.stderr.trim()}`,
      autoFixable: false,
    };
  }
  return { ok: true };
}

async function autoFixCH3(
  runner: Runner,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  const r = await runner("git", ["add", "_bmad-output/"], {
    cwd: opts.repoRoot,
  });
  if (r.exitCode !== 0) {
    return {
      ok: false,
      code: "CH3",
      hint: `CH3 auto-fix failed: ${r.stderr.trim()}`,
      autoFixable: false,
    };
  }
  return { ok: true };
}

async function autoFixCH5(
  runner: Runner,
  opts: PreflightOpts,
): Promise<PreflightResult> {
  const r = await runner("git", ["pull", "--rebase"], {
    cwd: opts.repoRoot,
  });
  if (r.exitCode === 0) {
    // Defensive: confirm the rebase fully completed. `git pull --rebase` can
    // exit 0 yet leave a half-rebased state if hooks or odd configs interfere.
    // If CH2 trips, abort and surface the conflict hint.
    const ch2 = await detectCH2(runner, opts);
    if (!ch2.ok) {
      await runner("git", ["rebase", "--abort"], { cwd: opts.repoRoot });
      return {
        ok: false,
        code: "CH5",
        hint: "CH5 auto-fix produced conflicts; aborted. Resolve manually first.",
        autoFixable: false,
      };
    }
    return { ok: true };
  }
  // Conflict — abort the rebase so we never leave a half-rebased tree.
  await runner("git", ["rebase", "--abort"], { cwd: opts.repoRoot });
  return {
    ok: false,
    code: "CH5",
    hint: "CH5 auto-fix produced conflicts; aborted. Resolve manually first.",
    autoFixable: false,
  };
}
