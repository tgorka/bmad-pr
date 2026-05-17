import { randomUUID } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  unlinkSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { BmadPrError, type LedgerEntry, type StoryId } from "./types.ts";

export type Ledger = {
  exists: boolean;
  frontmatter: Record<string, unknown>;
  prs: LedgerEntry[];
  body: string;
};

const FRONTMATTER_RE = /^---\r?\n([\s\S]*?)\r?\n^---\r?\n?([\s\S]*)$/m;
const STORY_ID_RE = /^(\d+)\.(\d+)$/;

export function parseStoryId(input: string): StoryId {
  const m = STORY_ID_RE.exec(input);
  if (!m?.[1] || !m?.[2]) {
    throw new BmadPrError(
      "refuse",
      `--story must be <epic>.<story> (e.g. 3.2), got '${input}'`,
    );
  }
  const epic = Number.parseInt(m[1], 10);
  const story = Number.parseInt(m[2], 10);
  if (epic < 1 || story < 1) {
    throw new BmadPrError(
      "refuse",
      `--story epic and story numbers must be >= 1, got '${input}'`,
    );
  }
  return { epic, story };
}

export function resolveStoryPath(repoRoot: string, id: StoryId): string {
  return join(repoRoot, "_bmad-output", "stories", `${id.epic}.${id.story}.md`);
}

export async function loadLedger(path: string): Promise<Ledger> {
  if (!existsSync(path)) {
    return { exists: false, frontmatter: {}, prs: [], body: "" };
  }
  const text = readFileSync(path, "utf8");
  const m = FRONTMATTER_RE.exec(text);
  if (!m) {
    return { exists: true, frontmatter: {}, prs: [], body: text };
  }
  const fmText = m[1] ?? "";
  const body = m[2] ?? "";
  const fm = parseYaml(fmText, path);
  const prs = extractPrs(fm, path);
  const frontmatter = { ...fm };
  delete frontmatter.prs;
  return { exists: true, frontmatter, prs, body };
}

export type FindEntryPredicate = { phase: string };

export function findEntry(
  prs: readonly LedgerEntry[],
  q: FindEntryPredicate,
): LedgerEntry | null {
  return prs.find((e) => e.phase === q.phase && e.status === "open") ?? null;
}

export async function appendEntry(
  path: string,
  id: StoryId,
  entry: LedgerEntry,
): Promise<void> {
  const current = await loadLedger(path);
  const fm: Record<string, unknown> = current.exists
    ? { ...current.frontmatter }
    : {};
  if (fm.epic === undefined) fm.epic = id.epic;
  if (fm.story === undefined) fm.story = id.story;
  const prs = [...current.prs, entry];
  await atomicWrite(path, serializeFile(fm, prs, current.body));
}

export async function updateEntry(
  path: string,
  predicate: (e: LedgerEntry) => boolean,
  mutator: (e: LedgerEntry) => LedgerEntry,
): Promise<void> {
  const current = await loadLedger(path);
  let matched = false;
  const prs = current.prs.map((e) => {
    if (!matched && predicate(e)) {
      matched = true;
      return mutator(e);
    }
    return e;
  });
  if (!matched) {
    throw new BmadPrError("fail", `no matching entry to update in ${path}`);
  }
  await atomicWrite(
    path,
    serializeFile(current.frontmatter, prs, current.body),
  );
}

function parseYaml(text: string, path: string): Record<string, unknown> {
  try {
    const parsed = Bun.YAML.parse(text);
    if (
      parsed === null ||
      typeof parsed !== "object" ||
      Array.isArray(parsed)
    ) {
      return {};
    }
    return parsed as Record<string, unknown>;
  } catch (cause) {
    throw new BmadPrError(
      "fail",
      `failed to parse ledger frontmatter at ${path}: ${
        cause instanceof Error ? cause.message : String(cause)
      }`,
    );
  }
}

function extractPrs(fm: Record<string, unknown>, path: string): LedgerEntry[] {
  const raw = fm.prs;
  if (raw === undefined) return [];
  if (!Array.isArray(raw)) {
    throw new BmadPrError("refuse", `ledger 'prs' at ${path} must be a list`);
  }
  return raw.map((e, i) => validateEntry(e, i, path));
}

function validateEntry(raw: unknown, index: number, path: string): LedgerEntry {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new BmadPrError(
      "refuse",
      `malformed ledger at ${path}: entry ${index} is not an object`,
    );
  }
  const o = raw as Record<string, unknown>;
  const required = [
    "url",
    "phase",
    "status",
    "openedAt",
    "lastAmendedAt",
  ] as const;
  for (const k of required) {
    if (typeof o[k] !== "string" || o[k] === "") {
      throw new BmadPrError(
        "refuse",
        `malformed ledger at ${path}: entry ${index} missing '${k}'`,
      );
    }
  }
  const status = o.status as string;
  if (status !== "open" && status !== "merged" && status !== "closed") {
    throw new BmadPrError(
      "refuse",
      `malformed ledger at ${path}: entry ${index} has invalid status '${status}'`,
    );
  }
  const entry: LedgerEntry = {
    url: o.url as string,
    phase: o.phase as string,
    status,
    openedAt: o.openedAt as string,
    lastAmendedAt: o.lastAmendedAt as string,
  };
  if (typeof o.runId === "string" && o.runId !== "") {
    entry.runId = o.runId;
  }
  return entry;
}

const ENTRY_FIELD_ORDER: ReadonlyArray<keyof LedgerEntry> = [
  "url",
  "phase",
  "runId",
  "status",
  "openedAt",
  "lastAmendedAt",
];

const FRONTMATTER_FIELD_ORDER = ["epic", "story"] as const;

function serializeFile(
  frontmatter: Record<string, unknown>,
  prs: readonly LedgerEntry[],
  body: string,
): string {
  const lines: string[] = ["---"];
  const seen = new Set<string>();
  for (const k of FRONTMATTER_FIELD_ORDER) {
    if (frontmatter[k] !== undefined) {
      lines.push(`${k}: ${serializeScalar(frontmatter[k])}`);
      seen.add(k);
    }
  }
  for (const k of Object.keys(frontmatter)) {
    if (seen.has(k) || k === "prs") continue;
    lines.push(`${k}: ${serializeScalar(frontmatter[k])}`);
  }
  lines.push("prs:");
  if (prs.length === 0) {
    lines[lines.length - 1] = "prs: []";
  } else {
    for (const e of prs) {
      let first = true;
      for (const k of ENTRY_FIELD_ORDER) {
        const v = e[k];
        if (v === undefined) continue;
        const prefix = first ? "  - " : "    ";
        lines.push(`${prefix}${k}: ${serializeScalar(v)}`);
        first = false;
      }
    }
  }
  lines.push("---");
  const fmBlock = `${lines.join("\n")}\n`;
  if (body === "") {
    return fmBlock;
  }
  return `${fmBlock}\n${body.replace(/^\n+/, "")}`;
}

const YAML_RESERVED =
  /^(?:y|Y|yes|Yes|YES|n|N|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF|null|Null|NULL|~)$/;
const NUMERIC_LOOKING = /^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/;

function serializeScalar(v: unknown): string {
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (typeof v === "string") {
    if (
      v === "" ||
      YAML_RESERVED.test(v) ||
      NUMERIC_LOOKING.test(v) ||
      !/^[\w./:+\-@]+$/.test(v)
    ) {
      return JSON.stringify(v);
    }
    return v;
  }
  return JSON.stringify(v);
}

async function atomicWrite(path: string, content: string): Promise<void> {
  const dir = dirname(path);
  mkdirSync(dir, { recursive: true });
  const tmp = `${path}.tmp.${process.pid}.${Date.now()}.${randomUUID()}`;
  await Bun.write(tmp, content);
  try {
    renameSync(tmp, path);
  } catch (err) {
    try {
      unlinkSync(tmp);
    } catch {
      // best-effort cleanup
    }
    throw err;
  }
}
