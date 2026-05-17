export type BmadPrErrorCode = "refuse" | "fail";

export class BmadPrError extends Error {
  override readonly name = "BmadPrError";
  readonly code: BmadPrErrorCode;

  constructor(code: BmadPrErrorCode, message: string) {
    super(message);
    this.code = code;
  }
}

export type LedgerEntry = {
  url: string;
  phase: string;
  runId?: string;
  status: "open" | "merged" | "closed";
  openedAt: string;
  lastAmendedAt: string;
};

export type StoryId = {
  epic: number;
  story: number;
};

export type RunnerResult = {
  stdout: string;
  stderr: string;
  exitCode: number;
};

export type RunnerOpts = { cwd?: string };

export type Runner = (
  cmd: string,
  args: readonly string[],
  opts?: RunnerOpts,
) => Promise<RunnerResult>;

export type DriverOpts = { cwd?: string };
