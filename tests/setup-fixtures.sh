#!/bin/bash
# Setup test fixtures - creates isolated test project with config hierarchy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

echo "Setting up test fixtures..."

# Clean existing fixtures
rm -rf "$FIXTURES_DIR"
mkdir -p "$FIXTURES_DIR"

# Create directory hierarchy:
# fixtures/
#   home/
#     .config/mopc/config.json          (home config)
#   work/
#     .mopc-config.json                 (work config)
#     team/
#       .mopc-config.json               (team config)
#       projects/
#         test-project/
#           .claude/diary/.config.json  (project config)

mkdir -p "$FIXTURES_DIR/home/.config/mopc"
mkdir -p "$FIXTURES_DIR/work/team/projects/test-project/.claude/diary"

# Home config (global defaults)
cat > "$FIXTURES_DIR/home/.config/mopc/config.json" << 'EOF'
{
  "wrapper": {
    "minSessionSize": 5,
    "minDiaryCount": 2,
    "autoDiary": false
  },
  "recovery": {
    "minActivity": 10
  },
  "idleTime": {
    "thresholdMinutes": 5
  }
}
EOF

# Work config (overrides some settings)
cat > "$FIXTURES_DIR/work/.mopc-config.json" << 'EOF'
{
  "wrapper": {
    "minSessionSize": 20,
    "autoDiary": true
  },
  "recovery": {
    "minActivity": 8
  }
}
EOF

# Team config (overrides work settings)
cat > "$FIXTURES_DIR/work/team/.mopc-config.json" << 'EOF'
{
  "wrapper": {
    "minSessionSize": 30
  },
  "recovery": {
    "minActivity": 5
  },
  "idleTime": {
    "thresholdMinutes": 10
  }
}
EOF

# Project config (final overrides)
cat > "$FIXTURES_DIR/work/team/projects/test-project/.claude/diary/.config.json" << 'EOF'
{
  "wrapper": {
    "minDiaryCount": 8,
    "autoReflect": true
  },
  "claude": {
    "cmd": "echo",
    "env": {
      "TEST_VAR": "test_value",
      "REF_VAR": "$HOME"
    }
  }
}
EOF

# Create test transcript for recovery testing
mkdir -p "$FIXTURES_DIR/work/team/projects/test-project/.claude/diary/recovery"
cat > "$FIXTURES_DIR/test-transcript.jsonl" << 'EOF'
{"type":"user","message":{"role":"user","content":"Create a test file"},"timestamp":1704545000}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I'll create a test file for you."},{"type":"tool_use","id":"tool_1","name":"Write","input":{"file_path":"/tmp/test.txt","content":"Hello World"}}]},"timestamp":1704545001}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool_1","content":[{"type":"text","text":"File created successfully"}]}]},"timestamp":1704545002}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done! Created /tmp/test.txt"}]},"timestamp":1704545003}
EOF

echo "✓ Test fixtures created at: $FIXTURES_DIR"
echo ""
echo "Directory structure:"
tree -L 5 "$FIXTURES_DIR" 2>/dev/null || find "$FIXTURES_DIR" -type f
