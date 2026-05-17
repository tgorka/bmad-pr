export type LogSink = (chunk: string) => void;

export type Logger = {
  info: (msg: string) => void;
  warn: (msg: string) => void;
  error: (msg: string) => void;
};

const defaultSink: LogSink = (s) => {
  process.stderr.write(s);
};

export function createLogger(sink: LogSink = defaultSink): Logger {
  return {
    info: (msg) => sink(`${msg}\n`),
    warn: (msg) => sink(`warn: ${msg}\n`),
    error: (msg) => sink(`error: ${msg}\n`),
  };
}
