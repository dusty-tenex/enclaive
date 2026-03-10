import { existsSync, mkdirSync, readdirSync, copyFileSync, readFileSync, appendFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Copy templates into target directory, update .gitignore, print next steps.
 */
export function initProject(targetDir) {
  const templatesDir = join(__dirname, '..', 'templates');

  if (!existsSync(templatesDir)) {
    console.error('[FAIL] Templates directory not found at', templatesDir);
    process.exit(1);
  }

  // Ensure target directory exists
  if (!existsSync(targetDir)) {
    mkdirSync(targetDir, { recursive: true });
    console.log(`[INFO] Created directory: ${targetDir}`);
  }

  // Copy template files (excluding .gitkeep)
  const files = readdirSync(templatesDir).filter((f) => f !== '.gitkeep');
  let copied = 0;
  for (const file of files) {
    const src = join(templatesDir, file);
    const dest = join(targetDir, file);
    if (existsSync(dest)) {
      console.log(`[WARN] Skipping ${file} (already exists)`);
      continue;
    }
    copyFileSync(src, dest);
    console.log(`[OK] Copied ${file}`);
    copied++;
  }

  // Update .gitignore
  const gitignorePath = join(targetDir, '.gitignore');
  const ignoreEntries = ['.audit-logs/', 'node_modules/', '.env'];
  if (existsSync(gitignorePath)) {
    const content = readFileSync(gitignorePath, 'utf-8');
    const toAdd = ignoreEntries.filter((e) => !content.includes(e));
    if (toAdd.length > 0) {
      appendFileSync(gitignorePath, '\n# enclAIve\n' + toAdd.join('\n') + '\n');
      console.log(`[OK] Updated .gitignore with ${toAdd.length} entries`);
    }
  }

  console.log(`\n[INFO] Initialized enclaive in ${targetDir}`);
  if (copied === 0 && files.length === 0) {
    console.log('[INFO] No templates to copy yet (templates/ is empty)');
  }

  console.log('\nNext steps:');
  console.log('  1. Copy your .env.example to .env and set ANTHROPIC_API_KEY');
  console.log('  2. Run: enclaive up');
  console.log('  3. Run: enclaive doctor');
  console.log('  4. Run: enclaive shell');
}
