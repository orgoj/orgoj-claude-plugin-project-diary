# REFACTOR-ZIG.md

Complete guide for migrating **Master of Prompts** from Bash/Node.js scripts to a single Zig CLI application.

## Table of Contents

1. [Project Overview](#project-overview)
2. [Why Zig?](#why-zig)
3. [Installing Zig](#installing-zig)
4. [Architecture: Single Binary with Subcommands](#architecture-single-binary-with-subcommands)
5. [Project Structure](#project-structure)
6. [Build System](#build-system)
7. [Installation & PATH Setup](#installation--path-setup)
8. [Migration Plan](#migration-plan)
9. [Zig Implementation Guide](#zig-implementation-guide)

---

## Project Overview

**Master of Prompts** (`mopc`) is a multi-AI CLI tool for managing session diaries, recovery, and reflection across AI models (Claude, Gemini, OpenCode, etc.).

**Binary name:** `mopc` (Master of Prompts CLI)
**Inspiration:** Metallica - Master of Puppets 🎸

### Current Architecture (Bash/Node.js)
- 4 separate scripts: wrapper, hook, tracker, recovery generator
- Dependencies: Bash, jq, Node.js
- Platform: Linux/macOS only

### Target Architecture (Zig)
- **1 binary** with subcommands
- Zero dependencies (static linking)
- Platform: Linux/Windows/macOS from single source

---

## Why Zig?

### Single Binary - Multiple Commands
- One executable (`mopc`) handles all functionality via subcommands
- Shared code compiled once (config loading, JSON parsing, path utils)
- Size: ~500-900 KB total (vs 1.6-3.2 MB for 4 separate binaries)

### Zero Dependencies
- Static linking - no Bash, jq, Node.js, Python required
- Cross-compilation built-in: one source → binaries for Linux/Windows/macOS
- Distribution: download one file, done

### Fast & Deterministic
- Startup time <1ms (vs 10-50ms for Bash+jq+node)
- Explicit memory management, no GC overhead
- Predictable resource usage

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

## Architecture: Single Binary with Subcommands

### Command Structure

**One binary, multiple subcommands:**

```bash
mopc wrapper [OPTIONS] -- [AI_CLI_OPTIONS]
mopc hook [session-start|pre-compact|session-end] [OPTIONS]
mopc tracker [stop|prompt] [OPTIONS]
mopc recovery [OPTIONS]
```

### Advantages Over Multiple Binaries

| Aspect | 4 Binaries | 1 Binary + Subcommands |
|--------|------------|------------------------|
| **Size** | 1.6-3.2 MB total | ~500-900 KB total |
| **Shared code** | Duplicated 4× | Compiled once |
| **Distribution** | 4 files to install | 1 file to install |
| **PATH setup** | Add directory or 4 symlinks | Add 1 binary |
| **Updates** | Replace 4 files | Replace 1 file |
| **Config loading** | 4× separate loads | 1× shared module |

### Command Mapping

| Original Script | Zig Subcommand | Purpose |
|----------------|----------------|---------|
| `bin/claude-diary` | `mopc wrapper` | Main CLI wrapper with session management |
| `hooks/diary-hook.sh` | `mopc hook` | Hook event dispatcher |
| `hooks/time-tracker.sh` | `mopc tracker` | Idle time tracking |
| `hooks/recovery-generator.js` | `mopc recovery` | Recovery file generator |

---

## Project Structure

```
orgoj-claude-plugin-project-diary/  # (will be renamed to master-of-prompts)
├── src/
│   ├── main.zig                 # Entry point - subcommand routing
│   ├── commands/
│   │   ├── wrapper.zig          # Wrapper command logic
│   │   ├── hook.zig             # Hook dispatcher
│   │   ├── tracker.zig          # Time tracker
│   │   └── recovery.zig         # Recovery generator
│   └── shared/
│       ├── config.zig           # Config loading (.claude/diary/.config.json)
│       ├── jsonl.zig            # JSONL transcript parsing
│       └── paths.zig            # Path utilities (cross-platform)
│
├── build.zig                    # Build configuration (single executable)
├── build.zig.zon                # Dependencies (if needed)
│
├── zig-out/
│   └── bin/
│       └── mopc                 # Single compiled binary (gitignored)
│
├── bin/
│   └── claude-diary → ../zig-out/bin/mopc  # Symlink for backwards compat
│
└── hooks/
    ├── hooks.json               # Updated to call `mopc hook`
    ├── diary-hook.sh → ../zig-out/bin/mopc  # Symlink (for hook system)
    ├── time-tracker.sh → ../zig-out/bin/mopc
    └── recovery-generator.js → ../zig-out/bin/mopc
```

### Why Symlinks for Hooks?

The hook system expects script names (`diary-hook.sh`, `time-tracker.sh`). Symlinks to `mopc` preserve backwards compatibility:

- `hooks.json` calls → `diary-hook.sh` (symlink to mopc)
- `mopc` inspects `argv[0]` to detect which command was called
- Alternatively, update `hooks.json` to call `mopc hook` directly

---

## Build System

### `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Single executable with all commands
    const exe = b.addExecutable(.{
        .name = "mopc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Run command (for development)
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run mopc");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run all tests");

    // Test main
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);
    test_step.dependOn(&run_main_tests.step);

    // Test commands
    const commands = [_][]const u8{ "wrapper", "hook", "tracker", "recovery" };
    inline for (commands) |cmd| {
        const cmd_test = b.addTest(.{
            .root_source_file = b.path(b.fmt("src/commands/{s}.zig", .{cmd})),
            .target = target,
            .optimize = optimize,
        });
        const run_cmd_test = b.addRunArtifact(cmd_test);
        test_step.dependOn(&run_cmd_test.step);
    }

    // Test shared modules
    const shared_modules = [_][]const u8{ "config", "jsonl", "paths" };
    inline for (shared_modules) |mod| {
        const mod_test = b.addTest(.{
            .root_source_file = b.path(b.fmt("src/shared/{s}.zig", .{mod})),
            .target = target,
            .optimize = optimize,
        });
        const run_mod_test = b.addRunArtifact(mod_test);
        test_step.dependOn(&run_mod_test.step);
    }
}
```

### Building

```bash
# Build binary (debug)
zig build

# Build optimized (release)
zig build -Doptimize=ReleaseSafe

# Build for specific platform
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-macos
zig build -Dtarget=aarch64-macos

# Run directly (for testing)
zig build run -- wrapper --help
zig build run -- hook session-start

# Run tests
zig build test

# Clean
rm -rf zig-out zig-cache
```

**Output:** Binary at `zig-out/bin/mopc`

---

## Installation & PATH Setup

### Local Development (In Repository)

```bash
# Build binary
zig build -Doptimize=ReleaseSafe

# Create symlinks for backwards compatibility
ln -sf ../zig-out/bin/mopc bin/claude-diary

# Create hook symlinks (if using argv[0] detection)
ln -sf ../zig-out/bin/mopc hooks/diary-hook.sh
ln -sf ../zig-out/bin/mopc hooks/time-tracker.sh
ln -sf ../zig-out/bin/mopc hooks/recovery-generator.js

# OR update hooks.json to call mopc directly
# (see Migration Plan section)
```

### System-Wide Installation

**Linux/macOS:**
```bash
# Build release binary
zig build -Doptimize=ReleaseSafe

# Install to user bin directory
mkdir -p ~/.local/bin
cp zig-out/bin/mopc ~/.local/bin/

# Add to PATH (if not already)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
which mopc
mopc --version
```

**Windows:**
```powershell
# Build release binary
zig build -Doptimize=ReleaseSafe

# Create user bin directory
New-Item -Path "$env:USERPROFILE\.local\bin" -ItemType Directory -Force

# Copy binary
Copy-Item zig-out\bin\mopc.exe "$env:USERPROFILE\.local\bin\"

# Add to PATH permanently
[Environment]::SetEnvironmentVariable(
    "Path",
    "$env:USERPROFILE\.local\bin;" + [Environment]::GetEnvironmentVariable("Path", "User"),
    "User"
)

# Verify (restart terminal first)
where.exe mopc
mopc --version
```

### Plugin-Specific Setup

**Option 1: Update `hooks/hooks.json` to call mopc directly**
```json
{
  "SessionStart": {
    "command": "mopc hook --project-dir \"${PROJECT_DIR}\" session-start"
  },
  "PreCompact": {
    "command": "mopc hook --project-dir \"${PROJECT_DIR}\" pre-compact"
  },
  "SessionEnd": {
    "command": "mopc hook --project-dir \"${PROJECT_DIR}\" session-end"
  },
  "Stop": {
    "command": "mopc tracker --project-dir \"${PROJECT_DIR}\" stop"
  },
  "UserPromptSubmit": {
    "command": "mopc tracker --project-dir \"${PROJECT_DIR}\" prompt"
  }
}
```

**Option 2: Keep symlinks (backwards compatible)**
```bash
# Symlink mopc as script names
ln -sf ../zig-out/bin/mopc hooks/diary-hook.sh
ln -sf ../zig-out/bin/mopc hooks/time-tracker.sh

# mopc detects command from argv[0]
# (requires implementing argv[0] detection in main.zig)
```

**Update wrapper:**
```bash
# In repository root
ln -sf zig-out/bin/mopc bin/claude-diary

# Or call mopc wrapper directly
mopc wrapper
```

---

## Migration Plan

### Phase 1: Setup & Infrastructure

**Goal:** Zig toolchain + basic project structure

```bash
# 1. Install Zig
mise install zig@latest
mise use -g zig@latest

# 2. Create project structure
mkdir -p src/{commands,shared}

# 3. Create build.zig (see Build System section)

# 4. Create minimal main.zig
cat > src/main.zig << 'EOF'
const std = @import("std");

pub fn main() !void {
    std.debug.print("mopc v0.1.0 - Master of Prompts\n", .{});
}
EOF

# 5. Verify build works
zig build
./zig-out/bin/mopc
```

### Phase 2: Main Entry Point & Subcommand Routing

**Goal:** Implement command dispatcher

**File:** `src/main.zig`

```zig
const std = @import("std");
const wrapper = @import("commands/wrapper.zig");
const hook = @import("commands/hook.zig");
const tracker = @import("commands/tracker.zig");
const recovery = @import("commands/recovery.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "wrapper")) {
        try wrapper.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "hook")) {
        try hook.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "tracker")) {
        try tracker.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "recovery")) {
        try recovery.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "--version")) {
        std.debug.print("mopc v0.1.0 - Master of Prompts\n", .{});
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        try printUsage();
        return error.UnknownCommand;
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\mopc - Master of Prompts
        \\
        \\Usage:
        \\  mopc wrapper [OPTIONS] -- [AI_CLI_OPTIONS]
        \\  mopc hook [session-start|pre-compact|session-end] [OPTIONS]
        \\  mopc tracker [stop|prompt] [OPTIONS]
        \\  mopc recovery [OPTIONS]
        \\  mopc --version
        \\
    );
}
```

### Phase 3: Shared Libraries

**Goal:** Reusable code for all commands

**Files to create:**
- `src/shared/config.zig` - Config loading/parsing
- `src/shared/jsonl.zig` - JSONL transcript parsing
- `src/shared/paths.zig` - Path utilities

**Key features:**
- Config merging (defaults → user config)
- JSON validation
- JSONL line-by-line streaming
- Cross-platform path handling

**Example `src/shared/config.zig` stub:**
```zig
const std = @import("std");

pub const Config = struct {
    wrapper: WrapperConfig = .{},
    recovery: RecoveryConfig = .{},
    idleTime: IdleTimeConfig = .{},

    pub const WrapperConfig = struct {
        autoDiary: bool = false,
        autoReflect: bool = false,
        askBeforeDiary: bool = true,
        askBeforeReflect: bool = true,
        minSessionSize: u32 = 2,
        minDiaryCount: u32 = 1,
    };

    pub const RecoveryConfig = struct {
        minActivity: u32 = 1,
        limits: Limits = .{},

        pub const Limits = struct {
            userPrompts: u32 = 5,
            promptLength: u32 = 150,
            toolCalls: u32 = 10,
            lastMessageLength: u32 = 500,
            errors: u32 = 5,
        };
    };

    pub const IdleTimeConfig = struct {
        enabled: bool = true,
        thresholdMinutes: u32 = 5,
    };
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return Config{};
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

### Phase 4: Simplest Command (Tracker)

**Goal:** Learn Zig CLI patterns with minimal complexity

**File:** `src/commands/tracker.zig`

**Original:** `hooks/time-tracker.sh` (50 lines, simple file I/O)

**Rewrite steps:**
1. Parse arguments (`--project-dir`, `stop`/`prompt`)
2. Read/write timestamp files
3. Calculate time difference
4. Output JSON on idle threshold

**Why start here:** No complex JSON config, no JSONL parsing, straightforward logic.

**Stub:**
```zig
const std = @import("std");

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        return error.MissingSubcommand;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "stop")) {
        try handleStop(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "prompt")) {
        try handlePrompt(allocator, args[1..]);
    } else {
        return error.UnknownSubcommand;
    }
}

fn handleStop(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // TODO: Save timestamp
    std.debug.print("Tracker: stop\n", .{});
}

fn handlePrompt(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // TODO: Check idle time
    std.debug.print("Tracker: prompt\n", .{});
}
```

### Phase 5: Hook Dispatcher

**Goal:** Event routing and recovery triggering

**File:** `src/commands/hook.zig`

**Original:** `hooks/diary-hook.sh` (100 lines, JSON I/O, process execution)

**Rewrite steps:**
1. Parse arguments (`session-start`, `pre-compact`, `session-end`)
2. Read stdin JSON
3. Route to recovery command
4. Format output (`<session-info>`, `<recovery-context>`)

### Phase 6: Recovery Generator

**Goal:** JSONL transcript parsing

**File:** `src/commands/recovery.zig`

**Original:** `hooks/recovery-generator.js` (200 lines, complex JSONL parsing)

**Rewrite steps:**
1. Load config (limits, minActivity)
2. Stream JSONL transcript line-by-line
3. Parse user/assistant messages
4. Track activity metrics
5. Generate recovery markdown

**Why later:** Most complex, requires `shared/jsonl.zig` and `shared/config.zig`

### Phase 7: Wrapper CLI

**Goal:** Session management and automation

**File:** `src/commands/wrapper.zig`

**Original:** `bin/claude-diary` (240 lines, argument parsing, process execution)

**Rewrite steps:**
1. Parse CLI arguments with `--` separator
2. Load config
3. Check unprocessed diary count
4. Execute AI CLI with session ID
5. Offer/auto diary and reflect

### Phase 8: Testing & Validation

**Goal:** Ensure feature parity

```bash
# Run Zig tests
zig build test

# Compare outputs (Bash vs Zig)
bash hooks/time-tracker.sh stop
mopc tracker stop

# Test all commands
mopc wrapper --help
echo '{"session_id":"test"}' | mopc hook session-start
mopc tracker stop
mopc recovery --help
```

### Phase 9: Cutover

**Goal:** Replace Bash/Node.js with Zig binary

```bash
# Backup old scripts
mkdir -p legacy/
mv hooks/*.{sh,js} legacy/
mv bin/claude-diary legacy/

# Create symlinks
ln -sf ../zig-out/bin/mopc bin/claude-diary
ln -sf ../zig-out/bin/mopc hooks/diary-hook.sh
ln -sf ../zig-out/bin/mopc hooks/time-tracker.sh
ln -sf ../zig-out/bin/mopc hooks/recovery-generator.js

# Update hooks.json (or use symlinks with argv[0] detection)

# Test full workflow
mopc wrapper
```

---

## Zig Implementation Guide

### Subcommand Routing (Main)

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: mopc <command> [args...]\n", .{});
        return error.InvalidArgs;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "wrapper")) {
        const wrapper = @import("commands/wrapper.zig");
        try wrapper.run(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "hook")) {
        const hook = @import("commands/hook.zig");
        try hook.run(allocator, args[2..]);
    } else {
        return error.UnknownCommand;
    }
}
```

### Argument Parsing with Flags

```zig
const std = @import("std");

pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !struct {
    project_dir: ?[]const u8,
    subcommand: []const u8,
} {
    var project_dir: ?[]const u8 = null;
    var subcommand: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--project-dir")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            project_dir = args[i];
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            subcommand = arg;
            break;
        }
    }

    return .{
        .project_dir = project_dir,
        .subcommand = subcommand orelse return error.MissingSubcommand,
    };
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

fn runAICLI(allocator: std.mem.Allocator, cli_name: []const u8, session_id: []const u8) !void {
    const argv = &[_][]const u8{
        cli_name,
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
                return error.AIFailed;
            }
        },
        else => return error.AITerminated,
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

### Reading stdin (for hooks)

```zig
const std = @import("std");

fn readStdinJson(allocator: std.mem.Allocator) !std.json.Value {
    const stdin = std.io.getStdIn();
    const content = try stdin.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        content,
        .{}
    );

    return parsed.value;
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
- **Scripts:** 4 separate scripts (~600 lines total)
- **Startup:** 10-50ms per invocation
- **Size:** ~40 MB (Node.js runtime) + scripts
- **Platform:** Linux/macOS only (Windows requires WSL)
- **Distribution:** Users must install Bash, jq, Node.js
- **Debugging:** Shell script complexity, implicit behavior

### After (Zig)
- **Dependencies:** None (static binary)
- **Binary:** 1 executable with 4 subcommands (~500-900 KB)
- **Startup:** <1ms per invocation
- **Size:** ~500-900 KB total
- **Platform:** Native Linux/Windows/macOS from single source
- **Distribution:** Download one binary, done
- **Debugging:** Explicit logic, type safety, clear error messages

### Size Comparison

| Component | Bash/Node | Zig |
|-----------|-----------|-----|
| Runtime | ~40 MB (Node.js) | 0 B (static) |
| Scripts/Binary | ~20 KB | ~500-900 KB |
| **Total** | **~40 MB** | **~500-900 KB** |

**Zig is 40-80× smaller** when including runtime dependencies.

---

## Resources

- **Zig Documentation:** https://ziglang.org/documentation/master/
- **Zig Learn:** https://ziglearn.org/
- **Standard Library:** https://ziglang.org/documentation/master/std/
- **Build System Guide:** https://zig.guide/build-system/
- **Cross-Compilation:** https://ziglang.org/learn/overview/#cross-compiling-is-a-first-class-use-case
- **Process API:** https://ziglang.org/documentation/master/std/#std.process
- **JSON API:** https://ziglang.org/documentation/master/std/#std.json

---

## Next Steps

1. **Install Zig** via mise: `mise install zig@latest`
2. **Create structure:** `mkdir -p src/{commands,shared}`
3. **Copy build.zig** from this document
4. **Phase 2:** Implement main.zig with subcommand routing
5. **Phase 3:** Create shared modules (config, jsonl, paths)
6. **Phase 4:** Start with tracker (simplest command)
7. **Phases 5-7:** Implement hook, recovery, wrapper
8. **Phase 8-9:** Test and cutover

**Master of Prompts** - Multi-AI CLI tool 🎸
