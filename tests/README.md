# mopc Integration Tests

Integration tests for the Master of Prompts (mopc) binary.

## Structure

```
tests/
├── run-tests.sh              # Main test runner
├── setup-fixtures.sh         # Creates test fixtures
├── fixtures/                 # Test data (generated)
│   ├── home/                # Mock home directory
│   ├── work/                # Mock workspace
│   └── test-transcript.jsonl # Sample transcript
└── README.md                # This file
```

## Running Tests

### Run all tests

```bash
./tests/run-tests.sh
```

### Prerequisites

- Built mopc binary: `zig build -Doptimize=ReleaseSafe`
- Bash shell
- Standard Unix tools (grep, find, etc.)

## Test Coverage

### 1. Basic Commands
- ✓ `mopc --version` - Version output
- ✓ `mopc` (no args) - Help output

### 2. Config Cascade
- ✓ Multi-level config loading (home → work → team → project)
- ✓ Field-by-field merging
- ✓ Override precedence

### 3. Tracker Command
- ✓ `mopc tracker stop` - Timestamp creation
- ✓ `mopc tracker prompt` - Idle time detection
- ✓ Config loading and threshold handling

### 4. Recovery Command
- ✓ JSONL transcript parsing
- ✓ Recovery file generation
- ✓ Activity scoring
- ✓ Markdown formatting

### 5. Hook Command
- ✓ `mopc hook session-start` - Session info output
- ✓ Recovery context loading (when applicable)

## Test Fixtures

### Config Hierarchy

The test suite creates a realistic config hierarchy:

```
fixtures/home/.config/mopc/config.json
  wrapper.minSessionSize: 5
  wrapper.minDiaryCount: 2
  recovery.minActivity: 10

fixtures/work/.mopc-config.json
  wrapper.minSessionSize: 20  (overrides home)
  wrapper.autoDiary: true
  recovery.minActivity: 8

fixtures/work/team/.mopc-config.json
  wrapper.minSessionSize: 30  (overrides work)
  recovery.minActivity: 5
  idleTime.thresholdMinutes: 10

fixtures/work/team/projects/test-project/.claude/diary/.config.json
  wrapper.minDiaryCount: 8
  wrapper.autoReflect: true
  claude.cmd: "echo"
```

**Final merged config:**
- `minSessionSize`: 30 (from team, overriding work:20, home:5)
- `minDiaryCount`: 8 (from project, overriding home:2)
- `autoDiary`: true (from work)
- `minActivity`: 5 (from team, overriding work:8, home:10)
- `thresholdMinutes`: 10 (from team, overriding home:5)
- `autoReflect`: true (from project)

### Sample Transcript

`test-transcript.jsonl` contains a minimal valid transcript:
- User prompt: "Create a test file"
- Tool use: Write tool call
- Tool result: Success
- Assistant response: Confirmation

This tests JSONL parsing, tool call tracking, and file modification detection.

## Writing New Tests

### Test Function Template

```bash
test_my_feature() {
    echo_test "Description of test"

    # Setup
    local test_dir="/tmp/mopc-test-myfeature-$$"
    mkdir -p "$test_dir"

    # Execute
    output=$("$MOPC" command args 2>&1)

    # Assert
    assert_contains "$output" "expected" "Test description"
    assert_file_exists "$test_dir/file.txt" "File created"

    # Cleanup
    rm -rf "$test_dir"
}
```

### Assertion Functions

- `assert_equals <expected> <actual> <test_name>` - Exact match
- `assert_contains <haystack> <needle> <test_name>` - Substring match
- `assert_file_exists <path> <test_name>` - File existence

### Add to Main

Add your test function to `main()`:

```bash
main() {
    # ...
    test_my_feature
    # ...
}
```

## CI Integration

To run tests in CI:

```bash
#!/bin/bash
set -e

# Build
zig build -Doptimize=ReleaseSafe

# Test
./tests/run-tests.sh
```

## Troubleshooting

### Tests fail with "mopc not found"

Build the binary first:
```bash
zig build -Doptimize=ReleaseSafe
```

### Permission denied on test scripts

Make scripts executable:
```bash
chmod +x tests/*.sh
```

### Fixture setup fails

Run setup manually to debug:
```bash
bash tests/setup-fixtures.sh
```
