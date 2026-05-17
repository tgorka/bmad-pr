import {
  createDraftPr,
  detectGhOnPath,
  editPrBody,
  parsePrNumberFromUrl,
  pushBranch,
} from "../pr/gh-driver.ts";
import {
  appendEntry,
  findEntry,
  loadLedger,
  parseStoryId,
  resolveStoryPath,
  updateEntry,
} from "../pr/ledger.ts";
import { runCommand } from "../pr/runner.ts";
import { BmadPrError, type LedgerEntry, type Runner } from "../pr/types.ts";

export type RunOptions = {
  runner?: Runner;
  cwd?: string;
  stdoutSink?: (chunk: string) => void;
  stderrSink?: (chunk: string) => void;
  now?: () => Date;
};

type ParsedArgs = {
  help: boolean;
  story?: string;
  phase?: string;
  runId?: string;
  amend: boolean;
  dryRun: boolean;
  trunkBranch: string;
};

const HELP_TEXT = `Usage: bmad-pr [options]

Opens or amends a draft pull request via gh for a BMAD story phase, and
records the PR URL in the stories-file ledger.

Default behavior: looks up {story, phase} in the ledger. If no open entry
exists, opens a new draft PR. If an open entry exists, amends it
(pushes a new commit, refreshes the PR body, bumps lastAmendedAt). The
original runId is preserved on amend.

Options:
  --story <epic>.<story>    Required. Positive integers, e.g. 3.2
  --phase <name>            Required. e.g. dev-story
  --run-id <id>             Optional. BMAD run identifier (used only when
                            opening a new PR; ignored on amend).
  --amend                   Force the amend path; refuse if no open
                            ledger entry exists for {story, phase}.
  --dry-run                 Print the would-run plan; no git/gh/file ops.
  --trunk-branch <name>     Branch to refuse on (default: main).
  --help                    Show this message.

Exit codes:
  0  success
  2  refusal (precondition not met)
  1  unexpected failure
`;

export async function run(
  argv: readonly string[],
  opts: RunOptions = {},
): Promise<number> {
  const runner = opts.runner ?? runCommand;
  const cwd = opts.cwd ?? process.cwd();
  const stdout = opts.stdoutSink ?? ((s) => process.stdout.write(s));
  const stderr = opts.stderrSink ?? ((s) => process.stderr.write(s));
  const now = opts.now ?? (() => new Date());

  let parsed: ParsedArgs;
  try {
    parsed = parseArgs(argv);
  } catch (err) {
    return reportError(err, stderr);
  }

  if (parsed.help) {
    stdout(HELP_TEXT);
    return 0;
  }

  try {
    return await execute(parsed, { runner, cwd, stdout, stderr, now });
  } catch (err) {
    return reportError(err, stderr);
  }
}

type ExecCtx = {
  runner: Runner;
  cwd: string;
  stdout: (s: string) => void;
  stderr: (s: string) => void;
  now: () => Date;
};

async function execute(args: ParsedArgs, ctx: ExecCtx): Promise<number> {
  if (!args.story) {
    throw new BmadPrError("refuse", "--story is required");
  }
  if (!args.phase) {
    throw new BmadPrError("refuse", "--phase is required");
  }
  const id = parseStoryId(args.story);

  const repoRoot = await resolveRepoRoot(ctx.runner, ctx.cwd);
  const driverOpts = { cwd: repoRoot };
  const storyPath = resolveStoryPath(repoRoot, id);

  if (!(await detectGhOnPath(ctx.runner, driverOpts))) {
    throw new BmadPrError(
      "refuse",
      "'gh' CLI not on PATH. See: https://cli.github.com/",
    );
  }

  const branch = await detectBranch(ctx.runner, repoRoot);
  if (branch === args.trunkBranch) {
    throw new BmadPrError(
      "refuse",
      `on trunk branch '${branch}'. Run: git switch -c bmad/story/${id.epic}.${id.story}`,
    );
  }

  const ledger = await loadLedger(storyPath);
  const existing = findEntry(ledger.prs, { phase: args.phase });

  if (args.amend && !existing) {
    throw new BmadPrError(
      "refuse",
      `--amend requires an existing PR for ${args.story}/${args.phase}. Try: bmad-pr --story ${args.story} --phase ${args.phase} (without --amend) to open one.`,
    );
  }

  const nowIso = isoSeconds(ctx.now());
  const body = buildBody(id, args.phase, args.runId);
  const title = `BMAD: ${args.story} ${args.phase}`;

  if (existing) {
    const prNumber = parsePrNumberFromUrl(existing.url);
    if (prNumber === null) {
      throw new BmadPrError(
        "refuse",
        `malformed ledger at ${storyPath}: PR URL is unparseable: ${existing.url}`,
      );
    }
    if (args.dryRun) {
      ctx.stdout(`would run: git push -u origin HEAD (branch ${branch})\n`);
      ctx.stdout(`would run: gh pr edit ${prNumber} --body <body>\n`);
      ctx.stdout(
        `ledger diff: update entry for ${args.phase} → lastAmendedAt=${nowIso}\n`,
      );
      return 0;
    }
    const amendBody = buildBody(id, args.phase, existing.runId);
    await pushBranch(ctx.runner, driverOpts);
    await editPrBody(ctx.runner, { prNumber, body: amendBody }, driverOpts);
    await updateEntry(
      storyPath,
      (e) => e.phase === args.phase && e.status === "open",
      (e) => ({ ...e, lastAmendedAt: nowIso }),
    );
    ctx.stdout(`${existing.url}\n`);
    return 0;
  }

  const entry: LedgerEntry = {
    url: "(pending)",
    phase: args.phase,
    status: "open",
    openedAt: nowIso,
    lastAmendedAt: nowIso,
  };
  if (args.runId) entry.runId = args.runId;

  if (args.dryRun) {
    ctx.stdout(`would run: git push -u origin HEAD (branch ${branch})\n`);
    ctx.stdout(`would run: gh pr create --draft --title "${title}"\n`);
    ctx.stdout(
      `ledger diff: append entry { phase: ${args.phase}, status: open, openedAt: ${nowIso} }\n`,
    );
    return 0;
  }

  await pushBranch(ctx.runner, driverOpts);
  const url = await createDraftPr(ctx.runner, { title, body }, driverOpts);
  entry.url = url;
  await appendEntry(storyPath, id, entry);
  ctx.stdout(`${url}\n`);
  return 0;
}

async function resolveRepoRoot(runner: Runner, cwd: string): Promise<string> {
  const r = await runner("git", ["rev-parse", "--show-toplevel"], { cwd });
  if (r.exitCode !== 0) {
    const detail = r.stderr.trim() || `exit ${r.exitCode}`;
    throw new BmadPrError(
      "refuse",
      `git rev-parse --show-toplevel failed (cwd=${cwd}): ${detail}`,
    );
  }
  const root = r.stdout.trim();
  if (root === "") {
    throw new BmadPrError(
      "fail",
      `git rev-parse --show-toplevel returned empty stdout (cwd=${cwd})`,
    );
  }
  return root;
}

async function detectBranch(runner: Runner, cwd: string): Promise<string> {
  const r = await runner("git", ["rev-parse", "--abbrev-ref", "HEAD"], { cwd });
  if (r.exitCode !== 0) {
    throw new BmadPrError("fail", `git rev-parse failed: ${r.stderr.trim()}`);
  }
  return r.stdout.trim();
}

function buildBody(
  id: { epic: number; story: number },
  phase: string,
  runId: string | undefined,
): string {
  return [
    `BMAD slice for story ${id.epic}.${id.story} phase ${phase}.`,
    `See: _bmad-output/stories/${id.epic}.${id.story}.md`,
    `BMAD-Run-Id: ${runId ?? "none"}`,
  ].join("\n");
}

function isoSeconds(d: Date): string {
  return `${d.toISOString().slice(0, 19)}Z`;
}

function parseArgs(argv: readonly string[]): ParsedArgs {
  const out: ParsedArgs = {
    help: false,
    amend: false,
    dryRun: false,
    trunkBranch: "main",
  };
  const consumeValue = (flag: string, raw: string | undefined): string => {
    if (!raw || raw.startsWith("--")) {
      throw new BmadPrError("refuse", `${flag} requires a value`);
    }
    return raw;
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--help":
      case "-h":
        out.help = true;
        break;
      case "--amend":
        out.amend = true;
        break;
      case "--dry-run":
        out.dryRun = true;
        break;
      case "--story":
        out.story = consumeValue("--story", argv[++i]);
        break;
      case "--phase":
        out.phase = consumeValue("--phase", argv[++i]);
        break;
      case "--run-id":
        out.runId = consumeValue("--run-id", argv[++i]);
        break;
      case "--trunk-branch":
        out.trunkBranch = consumeValue("--trunk-branch", argv[++i]);
        break;
      default:
        throw new BmadPrError("refuse", `unknown flag: ${a ?? "(empty)"}`);
    }
  }
  return out;
}

function reportError(err: unknown, stderr: (s: string) => void): number {
  if (err instanceof BmadPrError) {
    stderr(`${err.code === "refuse" ? "Refuse" : "Error"}: ${err.message}\n`);
    return err.code === "refuse" ? 2 : 1;
  }
  stderr(`error: ${err instanceof Error ? err.message : String(err)}\n`);
  return 1;
}

if (import.meta.main) {
  const argv = Bun.argv.slice(2);
  run(argv)
    .then((code) => {
      process.stdout.write("", () => process.exit(code));
    })
    .catch((err: unknown) => {
      process.stderr.write(
        `error: ${err instanceof Error ? err.message : String(err)}\n`,
      );
      process.exit(1);
    });
}
