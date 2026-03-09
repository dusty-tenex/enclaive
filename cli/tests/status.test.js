import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { formatBlockSummary, doctorChecks } from '../src/status.js';

describe('formatBlockSummary', () => {
  it('should format counts correctly', () => {
    const counts = { memory: 3, exfil: 2, write: 1 };
    const result = formatBlockSummary(counts);
    assert.equal(result, '6 blocks (3 memory, 2 exfil, 1 write)');
  });

  it('should return "0 blocks" for empty counts', () => {
    const result = formatBlockSummary({});
    assert.equal(result, '0 blocks');
  });

  it('should handle single mode', () => {
    const result = formatBlockSummary({ memory: 5 });
    assert.equal(result, '5 blocks (5 memory)');
  });

  it('should sort by count descending', () => {
    const counts = { write: 1, memory: 10, exfil: 5 };
    const result = formatBlockSummary(counts);
    assert.ok(result.startsWith('16 blocks'));
    assert.ok(result.indexOf('memory') < result.indexOf('exfil'));
    assert.ok(result.indexOf('exfil') < result.indexOf('write'));
  });
});

describe('doctorChecks', () => {
  it('should be an array', () => {
    assert.ok(Array.isArray(doctorChecks));
  });

  it('should have at least 5 checks', () => {
    assert.ok(doctorChecks.length >= 5);
  });

  it('each check should have name and run function', () => {
    for (const check of doctorChecks) {
      assert.equal(typeof check.name, 'string', `Check missing name`);
      assert.equal(typeof check.run, 'function', `Check "${check.name}" missing run function`);
    }
  });

  it('should include Docker check', () => {
    assert.ok(doctorChecks.some((c) => c.name.includes('Docker')));
  });

  it('should include settings.json check', () => {
    assert.ok(doctorChecks.some((c) => c.name.includes('settings.json')));
  });
});
