#!/bin/bash
# Integration tests for mopc binary

set -uo pipefail  # Don't use -e to allow tests to fail without exiting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOPC="$PROJECT_ROOT/zig-out/bin/mopc"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
declare -a FAILED_TESTS=()

# Helper functions
echo_test() {
    echo -e "${BLUE}TEST:${NC} $1"
}

echo_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

echo_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$1")
}

echo_info() {
    echo -e "${YELLOW}INFO:${NC} $1"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    ((TESTS_TOTAL++))

    if [ "$expected" = "$actual" ]; then
        echo_pass "$test_name"
        return 0
    else
        echo_fail "$test_name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    ((TESTS_TOTAL++))

    if echo "$haystack" | grep -qF "$needle"; then
        echo_pass "$test_name"
        return 0
    else
        echo_fail "$test_name"
        echo "  Expected to contain: $needle"
        echo "  Actual output: $haystack"
        return 0  # Don't exit on assertion failure
    fi
}

assert_file_exists() {
    local filepath="$1"
    local test_name="$2"

    ((TESTS_TOTAL++))

    if [ -f "$filepath" ]; then
        echo_pass "$test_name"
        return 0
    else
        echo_fail "$test_name"
        echo "  File does not exist: $filepath"
        return 1
    fi
}

# Setup
setup() {
    echo -e "${BLUE}=== Setting up test environment ===${NC}"

    # Build mopc if not exists
    if [ ! -f "$MOPC" ]; then
        echo_info "Building mopc..."
        cd "$PROJECT_ROOT"
        zig build -Doptimize=ReleaseSafe
    fi

    # Setup fixtures
    echo_info "Setting up test fixtures..."
    bash "$SCRIPT_DIR/setup-fixtures.sh" > /dev/null 2>&1

    echo ""
}

# Cleanup
cleanup() {
    echo_info "Cleaning up test artifacts..."
    rm -rf /tmp/mopc-test-* 2>/dev/null || true
}

# Test: mopc --version
test_version() {
    echo_test "mopc --version"

    output=$("$MOPC" --version 2>&1)
    assert_contains "$output" "mopc v" "Version command shows version"
    assert_contains "$output" "Master of Prompts" "Version command shows name"
}

# Test: mopc help
test_help() {
    echo_test "mopc (no args, shows help)"

    output=$("$MOPC" 2>&1 || true)
    assert_contains "$output" "Usage:" "Help shows usage"
    assert_contains "$output" "mopc wrapper" "Help shows wrapper command"
    assert_contains "$output" "mopc tracker" "Help shows tracker command"
}

# Test: Config cascade
test_config_cascade() {
    echo_test "Config cascade with parent directories"

    local project_dir="$FIXTURES_DIR/work/team/projects/test-project"
    local home_dir="$FIXTURES_DIR/home"

    # Run test-config with mocked HOME
    output=$(HOME="$home_dir" "$MOPC" test-config "$project_dir" 2>&1)

    # Verify merged config values
    assert_contains "$output" "minSessionSize: 30" "Team config overrides work (30, not 20)"
    assert_contains "$output" "minDiaryCount: 8" "Project config applied (8)"
    assert_contains "$output" "autoDiary: true" "Work config inherited (true)"
    assert_contains "$output" "minActivity: 5" "Team config overrides home (5, not 10)"
    assert_contains "$output" "thresholdMinutes: 10" "Team config overrides home (10, not 5)"
}

# Test: Tracker stop
test_tracker_stop() {
    echo_test "Tracker stop command"

    local test_dir="/tmp/mopc-test-tracker-$$"
    mkdir -p "$test_dir/.claude/diary/timestamps"

    # Run tracker stop
    echo '{"session_id":"test-stop-123"}' | "$MOPC" tracker stop --project-dir "$test_dir" 2>&1

    # Check timestamp file was created
    assert_file_exists "$test_dir/.claude/diary/timestamps/test-stop-123.txt" "Timestamp file created"

    # Verify timestamp is a number
    local timestamp=$(cat "$test_dir/.claude/diary/timestamps/test-stop-123.txt")
    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        echo_pass "Timestamp is valid number"
        ((TESTS_TOTAL++))
        ((TESTS_PASSED++))
    else
        echo_fail "Timestamp is valid number"
        ((TESTS_TOTAL++))
        ((TESTS_FAILED++))
    fi

    rm -rf "$test_dir"
}

# Test: Tracker prompt (idle detection)
test_tracker_prompt() {
    echo_test "Tracker prompt command (idle detection)"

    local test_dir="/tmp/mopc-test-prompt-$$"
    mkdir -p "$test_dir/.claude/diary/timestamps"

    # Create config with low threshold
    mkdir -p "$test_dir/.claude/diary"
    cat > "$test_dir/.claude/diary/.config.json" << 'EOF'
{
  "idleTime": {
    "enabled": true,
    "thresholdMinutes": 1
  }
}
EOF

    # Create old timestamp (2 minutes ago)
    local old_timestamp=$(($(date +%s) - 120))
    echo "$old_timestamp" > "$test_dir/.claude/diary/timestamps/test-prompt-456.txt"

    # Run tracker prompt
    output=$(echo '{"session_id":"test-prompt-456"}' | "$MOPC" tracker prompt --project-dir "$test_dir" 2>&1)

    # Should output idle notification
    assert_contains "$output" "Uplynulo" "Idle notification generated"
    assert_contains "$output" "minut" "Notification mentions minutes"

    rm -rf "$test_dir"
}

# Test: Recovery command
test_recovery() {
    echo_test "Recovery command (JSONL parsing)"

    local test_dir="/tmp/mopc-test-recovery-$$"
    mkdir -p "$test_dir/.claude/diary/recovery"

    # Create minimal config
    mkdir -p "$test_dir/.claude/diary"
    cat > "$test_dir/.claude/diary/.config.json" << 'EOF'
{
  "recovery": {
    "minActivity": 1
  }
}
EOF

    # Run recovery with test transcript
    local transcript="$FIXTURES_DIR/test-transcript.jsonl"
    echo "{\"session_id\":\"test-rec-789\",\"transcript_path\":\"$transcript\",\"cwd\":\"$test_dir\"}" | \
        "$MOPC" recovery 2>&1

    # Check recovery file was created
    local recovery_files=$(find "$test_dir/.claude/diary/recovery" -name "*-test-rec-789.md" 2>/dev/null | wc -l)

    if [ "$recovery_files" -gt 0 ]; then
        echo_pass "Recovery file created"
        ((TESTS_TOTAL++))
        ((TESTS_PASSED++))

        # Check recovery file content
        local recovery_file=$(find "$test_dir/.claude/diary/recovery" -name "*-test-rec-789.md" | head -1)
        local content=$(cat "$recovery_file")

        assert_contains "$content" "Quick Insights" "Recovery has Quick Insights section"
        assert_contains "$content" "What Was Asked" "Recovery has user prompts"
        assert_contains "$content" "Files Modified" "Recovery has files section"
    else
        echo_fail "Recovery file created"
        ((TESTS_TOTAL++))
        ((TESTS_FAILED++))
    fi

    rm -rf "$test_dir"
}

# Test: Hook session-start
test_hook_session_start() {
    echo_test "Hook session-start command"

    local test_dir="/tmp/mopc-test-hook-$$"
    mkdir -p "$test_dir/.claude/diary"

    # Run session-start hook
    output=$(echo '{"session_id":"test-hook-123","cwd":"'"$test_dir"'","source":"startup"}' | \
        "$MOPC" hook session-start --project-dir "$test_dir" 2>&1)

    # Should output session info (in JSON format for SessionStart hook)
    assert_contains "$output" "session-info" "Session info tag present"
    assert_contains "$output" "SESSION_ID: test-hook-123" "Session ID in output"
    assert_contains "$output" "hookEventName" "JSON hook output format"

    rm -rf "$test_dir"
}

# Summary
print_summary() {
    echo ""
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo -e "Total:  $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        echo ""
        echo -e "${RED}Failed tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Main
main() {
    echo -e "${BLUE}=== mopc Integration Tests ===${NC}"
    echo ""

    setup

    # Run tests
    test_version
    test_help
    test_config_cascade
    test_tracker_stop
    test_tracker_prompt
    test_recovery
    test_hook_session_start

    cleanup
    print_summary
}

main "$@"
