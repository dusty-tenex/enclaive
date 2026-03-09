import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { findComposeFile, sandboxName } from '../src/docker.js';

describe('findComposeFile', () => {
  let tempDir;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'enclaive-test-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('should find docker-compose.yml', () => {
    writeFileSync(join(tempDir, 'docker-compose.yml'), 'version: "3"');
    const result = findComposeFile(tempDir);
    assert.equal(result, join(tempDir, 'docker-compose.yml'));
  });

  it('should find docker-compose.yaml', () => {
    writeFileSync(join(tempDir, 'docker-compose.yaml'), 'version: "3"');
    const result = findComposeFile(tempDir);
    assert.equal(result, join(tempDir, 'docker-compose.yaml'));
  });

  it('should find compose.yml', () => {
    writeFileSync(join(tempDir, 'compose.yml'), 'version: "3"');
    const result = findComposeFile(tempDir);
    assert.equal(result, join(tempDir, 'compose.yml'));
  });

  it('should find compose.yaml', () => {
    writeFileSync(join(tempDir, 'compose.yaml'), 'version: "3"');
    const result = findComposeFile(tempDir);
    assert.equal(result, join(tempDir, 'compose.yaml'));
  });

  it('should return null when no compose file exists', () => {
    const result = findComposeFile(tempDir);
    assert.equal(result, null);
  });

  it('should prefer docker-compose.yml over compose.yml', () => {
    writeFileSync(join(tempDir, 'docker-compose.yml'), 'version: "3"');
    writeFileSync(join(tempDir, 'compose.yml'), 'version: "3"');
    const result = findComposeFile(tempDir);
    assert.equal(result, join(tempDir, 'docker-compose.yml'));
  });
});

describe('sandboxName', () => {
  it('should derive name from directory basename', () => {
    assert.equal(sandboxName('/Users/me/my-project'), 'claude-my-project');
  });

  it('should handle nested paths', () => {
    assert.equal(sandboxName('/a/b/c/cool-app'), 'claude-cool-app');
  });

  it('should handle trailing slash', () => {
    // basename of '/foo/bar/' is 'bar' in node:path
    assert.equal(sandboxName('/foo/bar'), 'claude-bar');
  });
});
