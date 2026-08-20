#!/usr/bin/env node
'use strict';

// Thin launcher: the real work lives in install.sh, which ships in this
// package alongside statusline-command.sh. Because both files sit in the
// package directory, install.sh takes its local-copy path and never has to
// download anything.

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const pkgRoot = path.resolve(__dirname, '..');
const pkg = require(path.join(pkgRoot, 'package.json'));
const installer = path.join(pkgRoot, 'install.sh');

const args = process.argv.slice(2);

if (args.includes('--version') || args.includes('-v')) {
  console.log(pkg.version);
  process.exit(0);
}

if (args.includes('--help') || args.includes('-h')) {
  console.log(`status-bar-claude ${pkg.version}

Installs the Claude Code status line into ~/.claude/ and patches
~/.claude/settings.json.

  npx status-bar-claude

Options:
  -h, --help       show this message
  -v, --version    print the version

Environment:
  STATUSLINE_SKIP_DEPS=1   skip the bash/jq/git dependency check (no sudo)

Requires bash, jq and git. Docs: ${pkg.homepage}`);
  process.exit(0);
}

if (process.platform === 'win32') {
  console.error(
    'status-bar-claude: Windows is not supported directly — the status line is a ' +
    'bash script. Run this inside WSL or Git Bash.'
  );
  process.exit(1);
}

if (!fs.existsSync(installer)) {
  console.error(`status-bar-claude: install.sh missing from the package at ${pkgRoot}`);
  process.exit(1);
}

const result = spawnSync('bash', [installer], { stdio: 'inherit' });

if (result.error) {
  if (result.error.code === 'ENOENT') {
    console.error('status-bar-claude: bash not found on PATH — install bash and retry.');
    process.exit(1);
  }
  console.error(`status-bar-claude: ${result.error.message}`);
  process.exit(1);
}

if (result.signal) {
  console.error(`status-bar-claude: installer killed by ${result.signal}`);
  process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
