#!/usr/bin/env node
/**
 * SessionStart hook - Platform detection and mopc setup
 * Creates platform-appropriate symlink/copy so other hooks can call mopc directly
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Detect platform
const platformMap = {
  linux: 'linux',
  darwin: 'darwin',
  win32: 'windows'
};

const archMap = {
  x64: 'x64',
  arm64: 'arm64'
};

const os = platformMap[process.platform];
const arch = archMap[process.arch];

if (!os || !arch) {
  console.error(`Unsupported platform: ${process.platform} ${process.arch}`);
  process.exit(1);
}

const platform = `${os}-${arch}`;
const ext = os === 'windows' ? '.exe' : '';

// Paths
const pluginRoot = path.resolve(__dirname, '..');
const hooksTarget = path.join(pluginRoot, 'hooks', `mopc${ext}`);
const binTarget = path.join(pluginRoot, 'bin', `mopc${ext}`);

// Prefer dev build (zig-out/bin/mopc) if exists, otherwise use platform-specific
const devBin = path.join(pluginRoot, 'zig-out', 'bin', `mopc${ext}`);
const prodBin = path.join(pluginRoot, 'zig-out', 'bin', platform, `mopc${ext}`);

let sourceBin;
if (fs.existsSync(devBin)) {
  // Development mode - use direct build output
  sourceBin = devBin;
} else if (fs.existsSync(prodBin)) {
  // Production/marketplace mode - use platform-specific binary
  sourceBin = prodBin;
} else {
  console.error(`Error: mopc binary not found`);
  console.error(`Tried dev: ${devBin}`);
  console.error(`Tried prod: ${prodBin}`);
  process.exit(1);
}

// Create symlinks for both hooks/mopc and bin/mopc
const targets = [hooksTarget, binTarget];

for (const targetBin of targets) {
  // Remove old symlink/file if exists
  if (fs.existsSync(targetBin)) {
    try {
      fs.unlinkSync(targetBin);
    } catch (err) {
      // Ignore errors
    }
  }

  // Create symlink (or copy on Windows if symlink fails)
  try {
    if (os === 'windows') {
      // On Windows, copy the file (symlinks require admin rights)
      fs.copyFileSync(sourceBin, targetBin);
    } else {
      // On Unix, create symlink
      fs.symlinkSync(sourceBin, targetBin);
      // Make executable
      fs.chmodSync(targetBin, 0o755);
    }
  } catch (err) {
    console.error(`Failed to setup mopc at ${targetBin}: ${err.message}`);
    process.exit(1);
  }
}

// Read stdin for session context
let stdinData = '';
process.stdin.on('data', chunk => {
  stdinData += chunk.toString();
});

process.stdin.on('end', () => {
  let context = {};
  try {
    context = JSON.parse(stdinData);
  } catch (err) {
    // Ignore parse errors
  }

  const sessionId = context.session_id || 'unknown';
  const cwd = context.cwd || process.cwd();

  // Call the real mopc hook session-start
  const args = process.argv.slice(2); // Get arguments after script name
  const mopcArgs = ['hook', 'session-start', ...args];

  try {
    const output = execSync(`"${hooksTarget}" ${mopcArgs.map(a => `"${a}"`).join(' ')}`, {
      input: stdinData,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'inherit']
    });

    // Output the result from mopc
    process.stdout.write(output);
  } catch (err) {
    console.error(`Error calling mopc: ${err.message}`);
    process.exit(1);
  }
});
