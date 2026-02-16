# Development

Guide for contributors, developers, and those extending GlobalContext with custom projections or integrations.

## Table of Contents

- [Project Structure](#project-structure)
- [Running Tests](#running-tests)
- [Code Conventions](#code-conventions)
- [Adding Event Types](#adding-event-types)
- [Adding Projections](#adding-projections)
- [Testing Patterns](#testing-patterns)
- [Contributing](#contributing)

## Project Structure

```
GlobalContext/
├── src/
│   ├── bin/                       # Main executables
│   │   ├── gc-install             # Installation script
│   │   ├── gc-uninstall           # Uninstall script
│   │   ├── gc-init                # Store initialization
│   │   ├── gc-hook                # Hook wrapper
│   │   ├── gc-query               # Query CLI
│   │   ├── gc-doctor              # Health check
│   │   └── project                # Projection builder
│   ├── lib/                       # Shared libraries (Bash)
│   │   ├── paths.sh               # Path resolution
│   │   ├── session_meta.sh        # Session metadata
│   │   ├── session_read.sh        # Session reading
│   │   ├── session_resolve.sh     # Session ID resolution
│   │   ├── session_chain.sh       # Session parent chains
│   │   ├── context_loader.sh      # Context loading
│   │   ├── format_context.sh      # Output formatting
│   │   ├── event_write.sh         # Event writing
│   │   ├── atomic_write.sh        # Atomic file writes
│   │   ├── projection_check.sh    # Projection staleness
│   │   ├── projection_store.sh    # Projection storage
│   │   ├── session_dir.sh         # Session directory setup
│   │   ├── sanitize.sh            # ID sanitization
│   │   ├── config.sh              # Configuration
│   │   ├── version.sh             # Version management
│   │   ├── prerequisites.sh       # Dependency checks
│   │   ├── latest_symlink.sh      # Latest symlink management
│   │   └── debug_log.sh           # Debug logging
│   └── install-hooks.sh           # Hook installer (manual)
├── tests/
│   ├── bin/                       # Binary tests
│   │   ├── test_gc_init.sh
│   │   ├── test_gc_query_*.sh
│   │   └── test_gc_doctor.sh
│   ├── lib/                       # Library tests
│   │   ├── test_paths.sh
│   │   ├── test_session_*.sh
│   │   ├── test_event_write.sh
│   │   └── test_projection_*.sh
│   ├── integration/               # Integration tests
│   │   ├── test_storage_layer.sh
│   │   ├── test_concurrent_writes.sh
│   │   └── test_crash_recovery.sh
│   └── 06/                        # Plugin tests
│       ├── test_01_plugin_manifest.sh
│       └── test_06_context_recovery_skill.sh
├── plugin/                        # Plugin distribution
│   ├── .claude-plugin/
│   ├── hooks/
│   ├── commands/
│   ├── skills/
│   ├── agents/
│   ├── scripts/                   # Copies from src/bin/
│   └── lib/                       # Copies from src/lib/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DESIGN-AMENDMENTS.md
│   ├── REVIEW.md
│   └── wiki/                      # This wiki
├── stories/                       # Story specifications
│   ├── 01-event-capture.md
│   ├── 02-hook-integration.md
│   ├── 03-storage-layer.md
│   ├── 04-projection-engine.md
│   ├── 05-context-recovery.md
│   └── 06-plugin-packaging.md
├── plans/                         # Implementation plans
│   ├── 00-installation-plan.md
│   ├── 01-event-capture-plan.md
│   ├── 02-hook-integration-plan.md
│   ├── 03-storage-layer-plan.md
│   ├── 04-projection-engine-plan.md
│   ├── 05-context-recovery-plan.md
│   └── 06-plugin-packaging-plan.md
├── tasks/                         # Task breakdowns
│   └── 04-projection-engine/
│       ├── 01-base-path-resolution.md
│       ├── 02-projection-registry.md
│       └── ...
├── README.md
└── VERSION
```

### Directory Purposes

| Directory | Purpose |
|-----------|---------|
| `src/bin/` | User-facing executables |
| `src/lib/` | Reusable Bash libraries |
| `tests/` | Test suite (Bash and Node.js) |
| `plugin/` | Plugin distribution (copies from src/) |
| `docs/` | Design docs and wiki |
| `stories/` | Story specifications |
| `plans/` | Implementation plans |
| `tasks/` | Task breakdowns by story |

## Running Tests

GlobalContext uses Bash for write-side tests and Node.js for projection tests.

### Prerequisites

```bash
# Required
sudo apt install jq       # JSON processor
sudo apt install flock    # File locking

# For projection tests (Node.js)
# No npm install needed - uses built-in modules only
```

### Run All Tests

```bash
# From project root
cd /path/to/GlobalContext

# Run all Bash tests
for test in tests/bin/*.sh tests/lib/*.sh tests/integration/*.sh; do
  bash "$test"
done

# Run specific test
bash tests/bin/test_gc_init.sh
```

### Test Output

Tests use a simple assert pattern:

```bash
# Success
✓ test_gc_init_creates_directories
✓ test_gc_init_is_idempotent

# Failure
✗ test_gc_init_validates_permissions
  Expected: 700
  Got: 755
```

### Test Isolation

Each test runs in a temporary directory:

```bash
# Tests use CLAUDE_CONTEXT_PATH override
export CLAUDE_CONTEXT_PATH="/tmp/gc-test-$$"
gc-init
# ... test operations
rm -rf "$CLAUDE_CONTEXT_PATH"
```

### Performance Tests

```bash
# Capture 1000 events
bash tests/perf-test.sh

# Expected: < 50s for 1000 events
```

## Code Conventions

### Bash Scripts

#### Shebang and Options

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `set -e`: Exit on error (except in capture scripts)
- `set -u`: Error on undefined variables
- `set -o pipefail`: Fail on pipe errors

**Exception**: `capture-event` and `gc-hook` do NOT use `set -e` (must never crash).

#### Function Naming

```bash
# Public functions (library exports)
gc_derive_project_id() { ... }
gc_write_event() { ... }

# Private functions (internal helpers)
_gc_validate_session_id() { ... }
_gc_format_timestamp() { ... }
```

Prefix: `gc_` for public, `_gc_` for private.

#### Error Handling

```bash
# Check command success
if ! command -v jq &>/dev/null; then
  echo "error: jq not found" >&2
  return 1
fi

# Check file exists
if [[ ! -f "$file" ]]; then
  echo "error: file not found: $file" >&2
  return 2
fi

# Validate arguments
if [[ -z "$1" ]]; then
  echo "error: argument required" >&2
  return 1
fi
```

#### Output Conventions

```bash
# Stdout: data/results only
echo "$json_output"

# Stderr: errors, warnings, diagnostics
echo "warning: projection stale" >&2
echo "error: session not found" >&2

# Prefix errors
echo "[gc-query] error: invalid format" >&2
echo "[capture-event] warning: lock timeout" >&2
```

#### Variable Naming

```bash
# Constants (uppercase)
GC_ROOT="$HOME/.claude-context"
GC_EVENTS_DIR="$GC_ROOT/events"

# Local variables (lowercase)
local session_id="$1"
local project_id
project_id="$(gc_derive_project_id "$PWD")"

# Arrays (lowercase with _array suffix)
local event_files_array=()
```

#### Quoting

```bash
# Always quote variables
echo "$var"
cd "$dir"

# Quote file paths with spaces
cat "$HOME/My Documents/file.txt"

# Array expansion
for file in "${files[@]}"; do
  echo "$file"
done
```

#### Portable vs Bash-specific

```bash
# Portable (POSIX)
[ -f "$file" ]
test -d "$dir"

# Bash-specific (acceptable)
[[ -f "$file" ]]
local var="value"
${var^^}  # uppercase (GNU only, provide fallback)
```

Prefer portable where possible, but Bash-specific is acceptable for:
- `local` keyword
- `[[ ]]` conditionals
- Process substitution `<(...)`
- Arrays

### Node.js Code

#### Module Pattern

```javascript
// No imports (built-in modules only)
const fs = require('fs').promises;
const path = require('path');

// Export functions
module.exports = {
  buildTimeline,
  buildFilesTouched
};
```

#### Error Handling

```javascript
try {
  const data = await fs.readFile(path, 'utf8');
  return JSON.parse(data);
} catch (err) {
  if (err.code === 'ENOENT') {
    // File not found - expected case
    return null;
  }
  // Unexpected error - re-throw
  throw err;
}
```

#### Streaming

```javascript
// Stream events, don't load all into memory
async function* replayEvents(sessionDir) {
  const files = await fs.readdir(sessionDir);
  const eventFiles = files
    .filter(f => /^\d{6}\.json$/.test(f))
    .sort();

  for (const file of eventFiles) {
    const data = await fs.readFile(path.join(sessionDir, file), 'utf8');
    yield JSON.parse(data);
  }
}
```

#### Projection Handler Pattern

```javascript
const handler = {
  init() {
    return {
      entries: [],
      _last_sequence: 0
    };
  },

  handle(state, event) {
    // Process event, update state
    state.entries.push({
      sequence: event.sequence,
      summary: generateSummary(event)
    });
    state._last_sequence = event.sequence;
    return state;
  },

  finalize(state) {
    // Add metadata, return projection
    return {
      _projection_type: 'timeline',
      _projection_version: 1,
      _rebuilt_at: new Date().toISOString(),
      ...state
    };
  }
};
```

## Adding Event Types

### 1. Update Hook Configuration

Edit `plugin/hooks/hooks.json` (or `~/.claude/settings.json` for manual):

```json
{
  "hooks": {
    "NewHookName": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gc-hook NewEventType",
            "async": true,
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

### 2. Document Event Type

Add to `docs/wiki/Event-Types.md`:

```markdown
### NewEventType

**Hook**: `NewHookName` (async/sync)

**Purpose**: Describe what this event captures

**Data Schema**:
```json
{
  "session_id": "string",
  "field1": "value",
  "field2": 123
}
```

**Data Fields**:
| Field | Type | Description |
|-------|------|-------------|
| session_id | string | Session identifier |
| field1 | string | Description |
```

### 3. Update Projection Handlers

Each projection that should process this event needs updating:

**Timeline** (`src/lib/projections/timeline.js`):
```javascript
function generateSummary(event) {
  switch (event.event_type) {
    case 'NewEventType':
      return `New thing happened: ${event.data.field1}`;
    // ... other cases
  }
}
```

**Decisions** (if relevant):
```javascript
function handle(state, event) {
  if (event.event_type === 'NewEventType') {
    // Group logic for new event
  }
  return state;
}
```

### 4. Add Tests

```bash
# tests/lib/test_event_capture_new_type.sh
test_new_event_type_captured() {
  local payload='{"session_id":"test","field1":"value"}'
  echo "$payload" | capture-event NewEventType

  assert_file_exists "$GC_EVENTS_DIR/test-*/test/000001.json"
  assert_json_field "$event_file" ".event_type" "NewEventType"
}
```

## Adding Projections

### 1. Create Projection Handler

Create `src/lib/projections/my-projection.js`:

```javascript
module.exports = {
  name: 'my-projection',
  version: 1,
  outputFile: 'my-projection.json',

  init() {
    return {
      items: [],
      _last_sequence: 0
    };
  },

  handle(state, event) {
    // Process event
    if (event.event_type === 'UserPromptReceived') {
      state.items.push({
        sequence: event.sequence,
        prompt: event.data.prompt
      });
    }
    state._last_sequence = event.sequence;
    return state;
  },

  finalize(state) {
    return {
      _projection_type: 'my-projection',
      _projection_version: 1,
      _last_sequence: state._last_sequence,
      _rebuilt_at: new Date().toISOString(),
      items: state.items,
      count: state.items.length
    };
  }
};
```

### 2. Register in Registry

Edit `src/lib/projection-registry.js`:

```javascript
const myProjection = require('./projections/my-projection');

const registry = {
  timeline: { ... },
  'my-projection': {
    name: 'my-projection',
    description: 'Custom projection for X',
    handler: myProjection,
    formatters: {
      json: formatJson,
      text: formatText,
      markdown: formatMarkdown
    }
  }
};
```

### 3. Add Formatters

```javascript
function formatText(projection) {
  let output = `My Projection (${projection.count} items)\n`;
  output += '='.repeat(40) + '\n';
  projection.items.forEach(item => {
    output += `[${item.sequence}] ${item.prompt}\n`;
  });
  return output;
}

function formatMarkdown(projection) {
  let md = `# My Projection\n\n`;
  md += `**Items:** ${projection.count}\n\n`;
  projection.items.forEach(item => {
    md += `- [${item.sequence}] ${item.prompt}\n`;
  });
  return md;
}
```

### 4. Add to project CLI

The projection registry automatically makes it available:

```bash
project my-projection abc123
project my-projection latest --format markdown
```

### 5. Document

Add to `docs/wiki/Projections.md`:

```markdown
## My Projection

### Purpose
Explain what this projection does and when to use it.

### Output Schema
```json
{
  "_projection_type": "my-projection",
  "_projection_version": 1,
  "_last_sequence": 42,
  "items": [ ... ],
  "count": 10
}
```

### Use Cases
- Use case 1
- Use case 2
```

### 6. Add Tests

```javascript
// tests/projections/test_my_projection.js
const assert = require('assert');
const myProjection = require('../src/lib/projections/my-projection');

describe('My Projection', () => {
  it('should initialize with empty items', () => {
    const state = myProjection.init();
    assert.deepEqual(state.items, []);
  });

  it('should handle UserPromptReceived events', () => {
    let state = myProjection.init();
    const event = {
      sequence: 1,
      event_type: 'UserPromptReceived',
      data: { prompt: 'Test prompt' }
    };
    state = myProjection.handle(state, event);
    assert.equal(state.items.length, 1);
    assert.equal(state.items[0].prompt, 'Test prompt');
  });
});
```

## Testing Patterns

### Bash Test Pattern

```bash
#!/usr/bin/env bash
# tests/lib/test_my_feature.sh

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test-helpers.sh"

# Test isolation
setup_test_env() {
  export CLAUDE_CONTEXT_PATH="/tmp/gc-test-$$"
  mkdir -p "$CLAUDE_CONTEXT_PATH"
}

teardown_test_env() {
  rm -rf "$CLAUDE_CONTEXT_PATH"
}

# Test functions
test_feature_works() {
  local result
  result=$(my_function "arg1")
  assert_eq "$result" "expected"
}

test_feature_handles_error() {
  if my_function "" 2>/dev/null; then
    fail "Should have returned error"
  fi
  pass
}

# Run tests
setup_test_env
trap teardown_test_env EXIT

run_test test_feature_works
run_test test_feature_handles_error

echo "All tests passed"
```

### Test Helpers

```bash
# tests/test-helpers.sh

assert_eq() {
  local actual="$1"
  local expected="$2"
  if [[ "$actual" != "$expected" ]]; then
    echo "✗ Assertion failed"
    echo "  Expected: $expected"
    echo "  Got: $actual"
    return 1
  fi
}

assert_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "✗ File not found: $file"
    return 1
  fi
}

assert_json_field() {
  local file="$1"
  local jq_path="$2"
  local expected="$3"
  local actual
  actual=$(jq -r "$jq_path" "$file")
  assert_eq "$actual" "$expected"
}

pass() {
  echo "✓ $TEST_NAME"
}

fail() {
  echo "✗ $TEST_NAME: $1"
  return 1
}

run_test() {
  export TEST_NAME="$1"
  if "$@"; then
    pass
  else
    fail
    EXIT_CODE=1
  fi
}
```

### Integration Test Pattern

```bash
# tests/integration/test_end_to_end.sh

test_full_session_workflow() {
  # 1. Initialize
  gc-init

  # 2. Capture events
  echo '{"session_id":"test","source":"startup"}' | capture-event SessionStarted
  echo '{"session_id":"test","prompt":"Test"}' | capture-event UserPromptReceived

  # 3. Build projection
  project timeline test

  # 4. Query
  local result
  result=$(gc-query last --format json)

  # 5. Verify
  assert_json_field - ".prompts[0].prompt" "Test" <<< "$result"
}
```

### Concurrent Write Test

```bash
test_concurrent_event_capture() {
  local session_id="concurrent-test"

  # Launch 10 concurrent writes
  for i in {1..10}; do
    (
      echo "{\"session_id\":\"$session_id\",\"i\":$i}" | capture-event UserPromptReceived
    ) &
  done
  wait

  # Count events
  local count
  count=$(ls "$GC_EVENTS_DIR"/*/"$session_id"/[0-9]*.json | wc -l)
  assert_eq "$count" "10"

  # Verify no duplicate sequences
  local sequences
  sequences=$(ls "$GC_EVENTS_DIR"/*/"$session_id"/[0-9]*.json | xargs -n1 basename | sort)
  local unique
  unique=$(echo "$sequences" | uniq | wc -l)
  assert_eq "$unique" "10"
}
```

## Contributing

### Before Submitting

1. **Read design docs**:
   - `docs/ARCHITECTURE.md`
   - `docs/DESIGN-AMENDMENTS.md`
   - Story files in `stories/`

2. **Run tests**:
   ```bash
   bash tests/run-all.sh
   ```

3. **Check code style**:
   ```bash
   shellcheck src/bin/* src/lib/*.sh
   ```

4. **Update docs** if adding features:
   - Update relevant wiki page
   - Add examples
   - Document new flags/options

### Pull Request Checklist

- [ ] Tests added for new functionality
- [ ] All existing tests pass
- [ ] Documentation updated
- [ ] Code follows conventions
- [ ] No breaking changes (or clearly documented)
- [ ] Commit messages follow format: `feat(component): description` or `fix(component): description`

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `test`: Adding tests
- `refactor`: Code refactoring
- `perf`: Performance improvement

**Examples**:
```
feat(projections): add files-touched projection

Implements the files-touched projection that tracks all file operations
(read, write, edit, glob, grep) across a session.

Closes #42

fix(capture): handle empty stdin gracefully

capture-event now checks for empty stdin and logs warning instead of
crashing with jq parse error.

docs(wiki): add projection guide

Complete guide for understanding and using projections, including
schemas, use cases, and examples.
```

### Development Workflow

1. Fork repository
2. Create feature branch: `git checkout -b feat/my-feature`
3. Make changes
4. Add tests
5. Run test suite
6. Update documentation
7. Commit with conventional commits
8. Push and create PR

### Code Review Process

PRs are reviewed for:
- Design consistency with CQRS/Event Sourcing principles
- Test coverage
- Documentation completeness
- Code style adherence
- Backward compatibility

## Related Documentation

- [Architecture](Architecture.md) - System design
- [CLI Reference](CLI-Reference.md) - Command documentation
- [Event Types](Event-Types.md) - Event schemas
- [Projections](Projections.md) - Projection types
- [Plugin Guide](Plugin-Guide.md) - Plugin development
