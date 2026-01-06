# REFACTOR-ZIG.md

Complete guide for rewriting Bash/Node.js scripts to Zig CLI applications.

## Table of Contents

1. [Why Zig?](#why-zig)
2. [Installing Zig](#installing-zig)
3. [Project Structure](#project-structure)
4. [Binary Naming Convention](#binary-naming-convention)
5. [Build System](#build-system)
6. [Installation & PATH Setup](#installation--path-setup)
7. [Migration Plan](#migration-plan)
8. [Zig Implementation Guide](#zig-implementation-guide)

---

## Why Zig?

### Single Binary per Platform
- Static linking - no runtime dependencies (no Bash, jq, Node.js, Python)
- One source → binaries for Linux/Windows/macOS
- Cross-compilation built-in

### Fast & Deterministic
- Startup time <1ms (vs 10-50ms for Bash+jq+node)
- Explicit memory management
- No garbage collector overhead

### Multiplatform by Design
- Works natively on Windows (Bash scripts don't)
- Path handling abstractions (std.fs.path)
- Process execution (std.process)

### Developer Experience
- Simple, readable syntax
- Excellent standard library (JSON, filesystem, process)
- Built-in test framework
- Official docs: https://ziglang.org/documentation/master/

---

## Installing Zig

### Option 1: mise (Recommended)

**Install mise first:**
```bash
# Linux/macOS
curl https://mise.run | sh

# Or via package manager
brew install mise          # macOS
apt install mise           # Ubuntu/Debian
```

**Install Zig via mise:**
```bash
# Install latest stable
mise install zig@latest
mise use -g zig@latest

# Verify installation
zig version
```

**Benefits:**
- Version management (switch between Zig versions)
- Auto-activation per project
- Works with `.mise.toml` config

### Option 2: Direct Download

**Linux/macOS:**
```bash
# Download from https://ziglang.org/download/
cd ~/Downloads
tar xf zig-linux-x86_64-*.tar.xz
sudo mv zig-linux-x86_64-*/ /opt/zig
echo 'export PATH="/opt/zig:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Windows:**
```powershell
# Download from https://ziglang.org/download/
# Extract to C:\zig
# Add to PATH via System Properties → Environment Variables
```

### Option 3: Package Managers

```bash
# macOS
brew install zig

# Arch Linux
pacman -S zig

# Ubuntu/Debian (often outdated)
snap install zig --classic --beta
```

### Verify Installation

```bash
zig version
# Output: 0.13.0 or newer
```

---

## Project Structure

```
orgoj-claude-plugin-project-diary/
├── src/
│   ├── wrapper/
│   │   └── main.zig              # CLI wrapper (bin/claude-diary)
│   ├── hook/
│   │   └── main.zig              # Diary hook dispatcher (hooks/diary-hook.sh)
│   ├── tracker/
│   │   └── main.zig              # Idle time tracker (hooks/time-tracker.sh)
│   ├── recovery/
│   │   └── main.zig              # Recovery generator (hooks/recovery-generator.js)
│   └── shared/
│       ├── config.zig            # Config loading (.claude/diary/.config.json)
│       ├── jsonl.zig             # JSONL transcript parsing
│       └── paths.zig             # Path utilities
│
├── build.zig                     # Build configuration
├── build.zig.zon                 # Dependencies (if needed)
│
├── zig-out/
│   └── bin/                      # Compiled binaries (gitignored)
│       ├── claude-diary-wrapper
│       ├── claude-diary-hook
│       ├── claude-diary-tracker
│       └── claude-diary-recovery
│
├── bin/                          # Symlinks to zig-out/bin/ (gitignored)
│   └── claude-diary → ../zig-out/bin/claude-diary-wrapper
│
└── hooks/
    ├── hooks.json                # Updated to call Zig binaries
    ├── diary-hook.sh → ../zig-out/bin/claude-diary-hook
    ├── time-tracker.sh → ../zig-out/bin/claude-diary-tracker
    └── recovery-generator.js → ../zig-out/bin/claude-diary-recovery
```

---

## Binary Naming Convention

All binaries use the `claude-diary-*` prefix for clarity and namespace isolation:

| Original Script | Zig Binary | Purpose |
|----------------|------------|---------|
| `bin/claude-diary` | `claude-diary-wrapper` | Main CLI wrapper |
| `hooks/diary-hook.sh` | `claude-diary-hook` | Hook dispatcher |
| `hooks/time-tracker.sh` | `claude-diary-tracker` | Idle time tracking |
| `hooks/recovery-generator.js` | `claude-diary-recovery` | Recovery file generator |

**Rationale:**
- Clear namespace (`claude-diary-*`)
- Avoids conflicts with system binaries
- Easy to find via shell completion (`claude-diary-<TAB>`)
- Consistent with plugin naming

---

## Build System

### `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared module for common code
    const shared = b.addModule("shared", .{
        .root_source_file = b.path("src/shared/config.zig"),
    });

    // 1. Wrapper (main CLI)
    const wrapper = b.addExecutable(.{
        .name = "claude-diary-wrapper",
        .root_source_file = b.path("src/wrapper/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    wrapper.root_module.addImport("shared", shared);
    b.installArtifact(wrapper);

    // 2. Hook dispatcher
    const hook = b.addExecutable(.{
        .name = "claude-diary-hook",
        .root_source_file = b.path("src/hook/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    hook.root_module.addImport("shared", shared);
    b.installArtifact(hook);

    // 3. Time tracker
    const tracker = b.addExecutable(.{
        .name = "claude-diary-tracker",
        .root_source_file = b.path("src/tracker/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tracker.root_module.addImport("shared", shared);
    b.installArtifact(tracker);

    // 4. Recovery generator
    const recovery = b.addExecutable(.{
        .name = "claude-diary-recovery",
        .root_source_file = b.path("src/recovery/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    recovery.root_module.addImport("shared", shared);
    b.installArtifact(recovery);

    // Tests
    const test_step = b.step("test", "Run all tests");

    const wrapper_tests = b.addTest(.{
        .root_source_file = b.path("src/wrapper/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    wrapper_tests.root_module.addImport("shared", shared);

    const run_wrapper_tests = b.addRunArtifact(wrapper_tests);
    test_step.dependOn(&run_wrapper_tests.step);
}
```

### Building

```bash
# Build all binaries (debug)
zig build

# Build optimized (release)
zig build -Doptimize=ReleaseSafe

# Build for specific platform
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-macos
zig build -Dtarget=aarch64-macos

# Run tests
zig build test

# Clean
rm -rf zig-out zig-cache
```

**Output:** Binaries in `zig-out/bin/`

---

## Installation & PATH Setup

### Local Development (In Repository)

```bash
# Build binaries
zig build -Doptimize=ReleaseSafe

# Create symlinks for convenience
ln -sf ../zig-out/bin/claude-diary-wrapper bin/claude-diary
ln -sf ../zig-out/bin/claude-diary-hook hooks/diary-hook.sh
ln -sf ../zig-out/bin/claude-diary-tracker hooks/time-tracker.sh
ln -sf ../zig-out/bin/claude-diary-recovery hooks/recovery-generator.js

# Update hooks.json to use new binaries
# (see Migration Plan section)
```

### System-Wide Installation

**Linux/macOS:**
```bash
# Build release binaries
zig build -Doptimize=ReleaseSafe

# Install to user bin directory
mkdir -p ~/.local/bin
cp zig-out/bin/claude-diary-* ~/.local/bin/

# Add to PATH (if not already)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
which claude-diary-wrapper
```

**Windows:**
```powershell
# Build release binaries
zig build -Doptimize=ReleaseSafe

# Create user bin directory
New-Item -Path "$env:USERPROFILE\.local\bin" -ItemType Directory -Force

# Copy binaries
Copy-Item zig-out\bin\*.exe "$env:USERPROFILE\.local\bin\"

# Add to PATH permanently
[Environment]::SetEnvironmentVariable(
    "Path",
    "$env:USERPROFILE\.local\bin;" + [Environment]::GetEnvironmentVariable("Path", "User"),
    "User"
)

# Verify (restart terminal first)
where.exe claude-diary-wrapper
```

### Plugin-Specific Setup

**Update `hooks/hooks.json`:**
```json
{
  "SessionStart": {
    "command": "claude-diary-hook --project-dir \"${PROJECT_DIR}\" session-start"
  },
  "PreCompact": {
    "command": "claude-diary-hook --project-dir \"${PROJECT_DIR}\" pre-compact"
  },
  "SessionEnd": {
    "command": "claude-diary-hook --project-dir \"${PROJECT_DIR}\" session-end"
  },
  "Stop": {
    "command": "claude-diary-tracker --project-dir \"${PROJECT_DIR}\" stop"
  },
  "UserPromptSubmit": {
    "command": "claude-diary-tracker --project-dir \"${PROJECT_DIR}\" prompt"
  }
}
```

**Update wrapper symlink:**
```bash
# In repository root
ln -sf zig-out/bin/claude-diary-wrapper bin/claude-diary

# Or use directly
zig-out/bin/claude-diary-wrapper
```

---

## Migration Plan

### Phase 1: Setup & Infrastructure (Start Here)

**Goal:** Zig toolchain + basic project structure

```bash
# 1. Install Zig
mise install zig@latest
mise use -g zig@latest

# 2. Create project structure
mkdir -p src/{wrapper,hook,tracker,recovery,shared}

# 3. Create build.zig (see Build System section)

# 4. Verify build works
zig build
```

### Phase 2: Shared Libraries

**Goal:** Reusable code for all CLI apps

**Files to create:**
- `src/shared/config.zig` - Config loading/parsing
- `src/shared/jsonl.zig` - JSONL transcript parsing
- `src/shared/paths.zig` - Path utilities

**Key features:**
- Config merging (defaults → user config)
- JSON validation
- JSONL line-by-line streaming
- Cross-platform path handling

### Phase 3: Simplest CLI (Tracker)

**Goal:** Learn Zig CLI patterns with minimal complexity

**File:** `src/tracker/main.zig`

**Original:** `hooks/time-tracker.sh` (50 lines, simple file I/O)

**Rewrite steps:**
1. Parse arguments (`--project-dir`, `stop`/`prompt`)
2. Read/write timestamp files
3. Calculate time difference
4. Output JSON on idle threshold

**Why start here:** No JSON config, no JSONL parsing, straightforward logic.

### Phase 4: Hook Dispatcher

**Goal:** Event routing and recovery triggering

**File:** `src/hook/main.zig`

**Original:** `hooks/diary-hook.sh` (100 lines, JSON I/O, process execution)

**Rewrite steps:**
1. Parse arguments (`session-start`, `pre-compact`, `session-end`)
2. Read stdin JSON
3. Route to recovery generator
4. Format output (`<session-info>`, `<recovery-context>`)

### Phase 5: Recovery Generator

**Goal:** JSONL transcript parsing

**File:** `src/recovery/main.zig`

**Original:** `hooks/recovery-generator.js` (200 lines, complex JSONL parsing)

**Rewrite steps:**
1. Load config (limits, minActivity)
2. Stream JSONL transcript line-by-line
3. Parse user/assistant messages
4. Track activity metrics
5. Generate recovery markdown

**Why last:** Most complex, requires `shared/jsonl.zig`

### Phase 6: Wrapper CLI

**Goal:** Session management and automation

**File:** `src/wrapper/main.zig`

**Original:** `bin/claude-diary` (240 lines, argument parsing, process execution)

**Rewrite steps:**
1. Parse CLI arguments with `--` separator
2. Load config
3. Check unprocessed diary count
4. Execute Claude CLI with session ID
5. Offer/auto diary and reflect

### Phase 7: Testing & Validation

**Goal:** Ensure feature parity

```bash
# Run Zig tests
zig build test

# Compare outputs (Bash vs Zig)
bash hooks/time-tracker.sh stop
claude-diary-tracker stop

# Test all hooks
echo '{"session_id":"test"}' | claude-diary-hook session-start
```

### Phase 8: Cutover

**Goal:** Replace Bash/Node.js with Zig binaries

```bash
# Backup old scripts
mkdir -p legacy/
mv hooks/*.{sh,js} legacy/
mv bin/claude-diary legacy/

# Create symlinks
ln -sf ../zig-out/bin/claude-diary-wrapper bin/claude-diary
ln -sf ../zig-out/bin/claude-diary-hook hooks/diary-hook.sh
ln -sf ../zig-out/bin/claude-diary-tracker hooks/time-tracker.sh
ln -sf ../zig-out/bin/claude-diary-recovery hooks/recovery-generator.js

# Update hooks.json (already points to script names, symlinks handle rest)

# Test full workflow
bin/claude-diary
```

---

## Zig Implementation Guide

### Argument Parsing

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <command>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "start")) {
        try handleStart();
    } else if (std.mem.eql(u8, command, "stop")) {
        try handleStop();
    } else {
        return error.UnknownCommand;
    }
}
```

### JSON Config Loading

```zig
const std = @import("std");

const Config = struct {
    wrapper: WrapperConfig,

    const WrapperConfig = struct {
        autoDiary: bool = false,
        autoReflect: bool = false,
        minSessionSize: u32 = 2,
        minDiaryCount: u32 = 1,
    };
};

fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !Config {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return Config{ .wrapper = .{} }; // defaults
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(Config, allocator, content, .{});
    defer parsed.deinit();

    return parsed.value;
}
```

### JSONL Transcript Parsing

```zig
const std = @import("std");

fn parseTranscript(allocator: std.mem.Allocator, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();

    var line_buf: [4096]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            line,
            .{}
        ) catch continue; // skip malformed lines
        defer parsed.deinit();

        const entry = parsed.value;

        // Access fields
        if (entry.object.get("type")) |type_val| {
            const msg_type = type_val.string;

            if (std.mem.eql(u8, msg_type, "user")) {
                // Handle user message
                const message = entry.object.get("message").?;
                const content = message.object.get("content").?;
                // ...
            }
        }
    }
}
```

### Process Execution

```zig
const std = @import("std");

fn runClaude(allocator: std.mem.Allocator, session_id: []const u8) !void {
    const argv = &[_][]const u8{
        "claude",
        "code",
        "--session-id",
        session_id,
    };

    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                return error.ClaudeFailed;
            }
        },
        else => return error.ClaudeTerminated,
    }
}
```

### Cross-Platform Paths

```zig
const std = @import("std");

fn getDiaryDir(allocator: std.mem.Allocator, project_dir: []const u8) ![]u8 {
    const parts = &[_][]const u8{ project_dir, ".claude", "diary" };
    return try std.fs.path.join(allocator, parts);
}

fn ensureDirExists(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}
```

### Error Handling

```zig
const std = @import("std");

pub fn main() !void {
    run() catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn run() !void {
    // Main logic here
    const config = try loadConfig(allocator, ".config.json");
    try processData(config);
}
```

---

## Benefits Summary

### Before (Bash/Node.js)
- **Dependencies:** Bash, jq, Node.js, various shell utilities
- **Startup:** 10-50ms per hook invocation
- **Platform:** Linux/macOS only (Windows requires WSL)
- **Distribution:** Users must install all dependencies
- **Debugging:** Shell script complexity, implicit behavior

### After (Zig)
- **Dependencies:** None (static binary)
- **Startup:** <1ms per hook invocation
- **Platform:** Native Linux/Windows/macOS from single source
- **Distribution:** Download binary, done
- **Debugging:** Explicit logic, type safety, clear error messages

---

## Resources

- **Zig Documentation:** https://ziglang.org/documentation/master/
- **Zig Learn:** https://ziglearn.org/
- **Standard Library:** https://ziglang.org/documentation/master/std/
- **Build System Guide:** https://zig.guide/build-system/
- **Cross-Compilation:** https://ziglang.org/learn/overview/#cross-compiling-is-a-first-class-use-case

---

## Next Steps

1. **Install Zig** via mise: `mise install zig@latest`
2. **Create structure:** `mkdir -p src/{wrapper,hook,tracker,recovery,shared}`
3. **Copy build.zig** from this document
4. **Start with Phase 3:** Rewrite `time-tracker.sh` → `src/tracker/main.zig`
5. **Test iteratively:** Compare Bash vs Zig outputs
6. **Complete migration:** Follow phases 4-8

Good luck! 🚀
