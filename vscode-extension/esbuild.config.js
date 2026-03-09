const esbuild = require("esbuild");

const isWatch = process.argv.includes("--watch");

/** @type {import('esbuild').BuildOptions} */
const buildOptions = {
  entryPoints: ["src/extension.ts"],
  bundle: true,
  outfile: "out/extension.js",
  external: ["vscode"],
  format: "cjs",
  platform: "node",
  target: "node18",
  sourcemap: true,
  logLevel: "info",
};

async function main() {
  if (isWatch) {
    const ctx = await esbuild.context(buildOptions);
    await ctx.watch();
    console.log("[INFO] Watching for changes...");
  } else {
    await esbuild.build(buildOptions);
    console.log("[OK] Build complete.");
  }
}

main().catch((err) => {
  console.error("[FAIL] Build failed:", err);
  process.exit(1);
});
