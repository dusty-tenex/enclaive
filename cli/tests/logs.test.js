import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { parseLogLine, formatLogLine, filterLogs } from '../src/logs.js';

describe('parseLogLine', () => {
  it('should parse valid JSON', () => {
    const line = '{"timestamp":"2026-03-07T23:35:04Z","mode":"memory","file":"CLAUDE.md","tool":"Write","action":"BLOCKED","reason":"Instruction override","engine":"standalone"}';
    const result = parseLogLine(line);
    assert.equal(result.mode, 'memory');
    assert.equal(result.action, 'BLOCKED');
    assert.equal(result.file, 'CLAUDE.md');
    assert.equal(result.reason, 'Instruction override');
  });

  it('should return null for invalid JSON', () => {
    const result = parseLogLine('not json at all');
    assert.equal(result, null);
  });

  it('should return null for empty string', () => {
    assert.equal(parseLogLine(''), null);
  });

  it('should return null for null input', () => {
    assert.equal(parseLogLine(null), null);
  });

  it('should handle whitespace-padded JSON', () => {
    const result = parseLogLine('  {"action":"BLOCKED"}  ');
    assert.equal(result.action, 'BLOCKED');
  });
});

describe('formatLogLine', () => {
  const entry = {
    timestamp: '2026-03-07T23:35:04Z',
    mode: 'memory',
    file: 'CLAUDE.md',
    tool: 'Write',
    action: 'BLOCKED',
    reason: 'Instruction override',
  };

  it('should contain BLOCKED in output', () => {
    const output = formatLogLine(entry, { color: false });
    assert.ok(output.includes('BLOCKED'));
  });

  it('should contain mode in output', () => {
    const output = formatLogLine(entry, { color: false });
    assert.ok(output.includes('memory'));
  });

  it('should contain file in output', () => {
    const output = formatLogLine(entry, { color: false });
    assert.ok(output.includes('CLAUDE.md'));
  });

  it('should contain reason indented below', () => {
    const output = formatLogLine(entry, { color: false });
    assert.ok(output.includes('    Instruction override'));
  });

  it('should return empty string for null entry', () => {
    assert.equal(formatLogLine(null), '');
  });
});

describe('filterLogs', () => {
  const entries = [
    { mode: 'memory', action: 'BLOCKED' },
    { mode: 'exfil', action: 'BLOCKED' },
    { mode: 'memory', action: 'BLOCKED' },
    { mode: 'write', action: 'BLOCKED' },
  ];

  it('should filter by mode', () => {
    const result = filterLogs(entries, { mode: 'memory' });
    assert.equal(result.length, 2);
    assert.ok(result.every((e) => e.mode === 'memory'));
  });

  it('should return all entries when no filter', () => {
    const result = filterLogs(entries, {});
    assert.equal(result.length, 4);
  });

  it('should return all entries when mode is undefined', () => {
    const result = filterLogs(entries);
    assert.equal(result.length, 4);
  });

  it('should return empty array when no matches', () => {
    const result = filterLogs(entries, { mode: 'nonexistent' });
    assert.equal(result.length, 0);
  });
});
