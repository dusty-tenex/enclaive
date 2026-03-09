import { readFileSync, watchFile, unwatchFile, statSync } from 'node:fs';

/**
 * Parse a single JSONL line. Returns object or null on failure.
 */
export function parseLogLine(line) {
  if (!line || !line.trim()) return null;
  try {
    return JSON.parse(line.trim());
  } catch {
    return null;
  }
}

/**
 * Format a log entry for terminal display.
 * Time on left, BLOCKED in red, mode in yellow, file in white, reason indented below.
 * opts.color defaults to true.
 */
export function formatLogLine(entry, opts = {}) {
  const useColor = opts.color !== false;
  if (!entry) return '';

  const time = entry.timestamp || 'unknown';
  const action = entry.action || 'UNKNOWN';
  const mode = entry.mode || '';
  const file = entry.file || '';
  const reason = entry.reason || '';
  const tool = entry.tool || '';

  if (useColor) {
    const red = (s) => `\x1b[31m${s}\x1b[0m`;
    const yellow = (s) => `\x1b[33m${s}\x1b[0m`;
    const dim = (s) => `\x1b[2m${s}\x1b[0m`;

    const actionStr = action === 'BLOCKED' ? red(action) : action;
    const modeStr = yellow(mode);
    const parts = [`${dim(time)}  ${actionStr}  ${modeStr}  ${file}  [${tool}]`];
    if (reason) {
      parts.push(`    ${dim(reason)}`);
    }
    return parts.join('\n');
  }

  const parts = [`${time}  ${action}  ${mode}  ${file}  [${tool}]`];
  if (reason) {
    parts.push(`    ${reason}`);
  }
  return parts.join('\n');
}

/**
 * Filter log entries by mode.
 * opts.mode filters to only entries matching that mode.
 */
export function filterLogs(entries, opts = {}) {
  if (!opts.mode) return entries;
  return entries.filter((e) => e.mode === opts.mode);
}

/**
 * Read all entries from a JSONL log file.
 * Returns array of parsed objects (skipping invalid lines).
 */
export function readLogFile(logPath) {
  try {
    const content = readFileSync(logPath, 'utf-8');
    const lines = content.split('\n');
    return lines.map(parseLogLine).filter(Boolean);
  } catch {
    return [];
  }
}

/**
 * Count BLOCKED entries by mode.
 * Returns object like { memory: 3, exfil: 2 }.
 */
export function countByMode(entries) {
  const counts = {};
  for (const entry of entries) {
    if (entry.action === 'BLOCKED' && entry.mode) {
      counts[entry.mode] = (counts[entry.mode] || 0) + 1;
    }
  }
  return counts;
}

/**
 * Watch a log file for new entries and call onEntry for each.
 * Returns a cleanup function to stop watching.
 */
export function tailLog(logPath, onEntry) {
  let lastSize = 0;
  try {
    lastSize = statSync(logPath).size;
  } catch {
    // file may not exist yet
  }

  const check = () => {
    try {
      const content = readFileSync(logPath, 'utf-8');
      const currentSize = Buffer.byteLength(content, 'utf-8');
      if (currentSize > lastSize) {
        const newContent = content.slice(lastSize);
        const lines = newContent.split('\n');
        for (const line of lines) {
          const entry = parseLogLine(line);
          if (entry) {
            onEntry(entry);
          }
        }
        lastSize = currentSize;
      }
    } catch {
      // file may not exist yet
    }
  };

  watchFile(logPath, { interval: 500 }, check);

  return () => {
    unwatchFile(logPath, check);
  };
}
