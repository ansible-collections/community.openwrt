// Copyright (c) Vladimir Ermakov (@vooon)
// GNU General Public License v3.0+ (see LICENSES/GPL-3.0-or-later.txt or https://www.gnu.org/licenses/gpl-3.0.txt)
// SPDX-License-Identifier: GPL-3.0-or-later

/*
 * uc-lint.mjs - ucode linter built on ucode-lsp (https://github.com/NoahBPeterson/ucode-lsp).
 *
 * Runs `ucode-lsp`'s CLI checker (type inference, flow analysis, null-safety,
 * unused imports, forward-declarations) against the collection's `.uc` files,
 * gated to the oldest supported OpenWrt release (25.12.x) via `--target-version`.
 *
 * ucode-lsp resolves relative `import { ... } from './x.uc'` from the importing
 * file's directory, matching how the collection's action plugin transfers
 * `_ansible_common.uc` next to each module at runtime. So before checking the
 * modules we stage a copy of the shared helper next to each `.uc` module.
 *
 * ucode-lsp does NOT enforce every ucode-only rule, so we also keep the one
 * that real ucode (25.12.x) hard-requires and that the LSP does not flag:
 *   - `export function foo(){...}` must be terminated with `;`
 *     (ucode parses the export as an expression statement)
 *
 * Usage: node tests/uc-lint.mjs
 */
import { copyFileSync, existsSync, mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const repoRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const modulesDir = path.join(repoRoot, 'plugins/modules');
const moduleUtilsDir = path.join(repoRoot, 'plugins/module_utils');
const TARGET_VERSION = '25.12';

let failed = 0;

function err(msg) {
	console.error(`[uc-lint] ${msg}`);
	failed = 1;
}

function warn(msg) {
	console.warn(`[uc-lint] warning: ${msg}`);
}

function findUcFiles(dir) {
	if (!statSync(dir, { throwIfNoEntry: false })?.isDirectory())
		return [];
	return readdirSync(dir)
		.filter((f) => f.endsWith('.uc'))
		.map((f) => path.join(dir, f));
}

// Stage `_ansible_common.uc` next to each module so relative imports resolve the
// same way the runtime action plugin lays them out. Returns a temp dir holding
// a `plugins/modules` tree, or null if there is nothing to check.
function stageModules() {
	const moduleFiles = findUcFiles(modulesDir);
	const utilFiles = findUcFiles(moduleUtilsDir);
	if (moduleFiles.length === 0 && utilFiles.length === 0)
		return null;

	const staging = mkdtempSync(path.join(tmpdir(), 'uc-lint-'));
	const stagedModules = path.join(staging, 'plugins/modules');
	mkdirSync(stagedModules, { recursive: true });

	// Copy the shared helpers once each (their names cannot collide), then every
	// module, so each utility lands next to each module exactly once.
	for (const uf of utilFiles)
		copyFileSync(uf, path.join(stagedModules, path.basename(uf)));
	for (const mf of moduleFiles)
		copyFileSync(mf, path.join(stagedModules, path.basename(mf)));

	return staging;
}

// 1) ucode-lsp CLI checker (type/flow/null-safety/version-gated).
// Pin the ucode-lsp version for reproducibility (supply-chain safety in the
// pre-commit hook). Bump deliberately.
const UCODE_LSP_VERSION = '0.8.11';

function runUcodeLsp(staging) {
	const dir = staging ? path.join(staging, 'plugins/modules') : modulesDir;
	if (!existsSync(dir))
		return;
	const r = spawnSync('npx', ['-y', `ucode-lsp@${UCODE_LSP_VERSION}`, dir, '--target-version', TARGET_VERSION], {
		encoding: 'utf8',
		cwd: repoRoot,
	});
	if (r.status !== 0)
		err(`ucode-lsp (target ${TARGET_VERSION}) found issues:\n${r.stdout || r.stderr}`);
}

// 2) ucode-only rule: `export function foo(){...}` must be terminated with `;`.
function checkExportSemicolons(dir) {
	for (const file of findUcFiles(dir)) {
		const src = readFileSync(file, 'utf8');
		for (const m of src.matchAll(/export function\s+\w+\s*\([^)]*\)\s*\{/g)) {
			let i = m.index + m[0].length;   // just past the opening '{'
			let depth = 1;
			while (depth > 0 && i < src.length) {
				const c = src[i];
				if (c === '{') depth++;
				else if (c === '}') depth--;
				i++;
			}
			if (src[i] !== ';')
				err(`${path.relative(repoRoot, file)}: export function not terminated with ';': ${m[0].replace(/\s+/g, ' ')}`);
		}
	}
}

const staging = stageModules();
try {
	runUcodeLsp(staging);
	// Check the semicolon rule against the staged modules so relative paths stay
	// consistent, falling back to the source tree when nothing was staged.
	checkExportSemicolons(staging ? path.join(staging, 'plugins/modules') : modulesDir);
} finally {
	if (staging)
		rmSync(staging, { recursive: true, force: true });
}

if (failed)
	process.exit(1);
console.log('[uc-lint] all modules OK');