#!/usr/bin/env bash
# test_gc_dashboard_js.sh -- Validate that inline JS in gc-dashboard parses correctly.
# Catches template literal escaping bugs (e.g. unescaped backslash-quotes) that
# cause SyntaxError in the browser but pass Node.js source-level syntax checks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD="$SCRIPT_DIR/../../src/bin/gc-dashboard"

pass=0
fail=0

_pass() { echo "  PASS: $1"; pass=$((pass + 1)); }
_fail() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== Dashboard inline JS validation ==="

# Test 1: Source file passes Node.js syntax check
echo ""
echo "Test: Source file syntax"
if node -c "$DASHBOARD" 2>/dev/null; then
  _pass "node -c passes"
else
  _fail "node -c fails"
fi

# Test 2: Inline JS within the HTML template literal parses as valid JS
echo ""
echo "Test: Inline JS parses correctly (no template literal escaping issues)"
result=$(node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8");
const htmlStart = src.indexOf("`<!DOCTYPE");
const htmlEnd = src.indexOf("</html>`");
if (htmlStart === -1 || htmlEnd === -1) {
  console.log("ERROR: cannot find HTML template literal");
  process.exit(2);
}
const html = src.slice(htmlStart + 1, htmlEnd + 7);
const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
if (!scriptMatch) {
  console.log("ERROR: no <script> block found in HTML");
  process.exit(2);
}
try {
  new Function(scriptMatch[1]);
  console.log("OK");
} catch (e) {
  console.log("PARSE_ERROR: " + e.message);
  process.exit(1);
}
' "$DASHBOARD" 2>&1) || true

if [[ "$result" == "OK" ]]; then
  _pass "inline JS parses without errors"
else
  _fail "inline JS parse error: $result"
fi

# Test 3: No unescaped backslash-quotes in inline JS (common template literal bug)
echo ""
echo "Test: No dangerous backslash-quote patterns in HTML template"
# Extract just the HTML template and look for \' patterns that would break in browser
bq_count=$(node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8");
const htmlStart = src.indexOf("`<!DOCTYPE");
const htmlEnd = src.indexOf("</html>`");
const html = src.slice(htmlStart + 1, htmlEnd + 7);
// Count occurrences of backslash-single-quote outside of regex patterns
const lines = html.split("\n");
let count = 0;
for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  // Skip lines that are regex patterns (contain /.../)
  if (/\/[^/]+\\'"'"'[^/]*\//.test(line)) continue;
  // Check for literal \x27 pattern (backslash followed by single quote)
  const matches = line.match(/\\'"'"'/g);
  if (matches) {
    count += matches.length;
    console.error("  Line " + (i+1) + ": " + line.trim().substring(0, 80));
  }
}
console.log(count);
' "$DASHBOARD" 2>&1)

# Extract just the number (last line)
count_num=$(echo "$bq_count" | tail -1)
if [[ "$count_num" == "0" ]]; then
  _pass "no backslash-quote patterns in template HTML"
else
  _fail "found $count_num backslash-quote patterns in template (may break in browser)"
  echo "$bq_count" | head -10
fi

# Test 4: All HTML tab buttons have matching switchView targets
echo ""
echo "Test: Tab buttons have matching view containers"
node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8");
const htmlStart = src.indexOf("`<!DOCTYPE");
const htmlEnd = src.indexOf("</html>`");
const html = src.slice(htmlStart + 1, htmlEnd + 7);

// Find all switchView calls in onclick
const tabMatches = [...html.matchAll(/onclick="switchView\('"'"'(\w+)'"'"'\)"/g)];
const tabs = tabMatches.map(m => m[1]);

let ok = true;
for (const tab of tabs) {
  // Each tab should have a corresponding view container
  // events -> eventFeed, usage -> usageView, search -> searchView
  const viewId = tab === "events" ? "eventFeed" : tab + "View";
  if (!html.includes("id=\"" + viewId + "\"")) {
    console.log("MISSING: view container #" + viewId + " for tab " + tab);
    ok = false;
  }
}
if (ok) {
  console.log("OK:" + tabs.join(","));
} else {
  process.exit(1);
}
' "$DASHBOARD" 2>&1
tab_result=$?
if [[ $tab_result -eq 0 ]]; then
  _pass "all tab buttons have matching view containers"
else
  _fail "missing view containers for some tabs"
fi

# Test 5: switchView function handles all tabs
echo ""
echo "Test: switchView handles all tab names"
node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8");
const htmlStart = src.indexOf("`<!DOCTYPE");
const htmlEnd = src.indexOf("</html>`");
const html = src.slice(htmlStart + 1, htmlEnd + 7);
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

// Find all tab names used in onclick
const tabMatches = [...html.matchAll(/onclick="switchView\('"'"'(\w+)'"'"'\)"/g)];
const tabs = tabMatches.map(m => m[1]);

// Check switchView references each tab
let ok = true;
for (const tab of tabs) {
  const tabId = "tab" + tab.charAt(0).toUpperCase() + tab.slice(1);
  if (!script.includes(tabId)) {
    console.log("MISSING: switchView does not reference #" + tabId);
    ok = false;
  }
}
if (ok) console.log("OK");
else process.exit(1);
' "$DASHBOARD" 2>&1
sv_result=$?
if [[ $sv_result -eq 0 ]]; then
  _pass "switchView handles all tab names"
else
  _fail "switchView missing tab handlers"
fi

# Summary
echo ""
echo "=============================="
echo "Results: $pass passed, $fail failed"
echo "=============================="

[[ $fail -eq 0 ]] && exit 0 || exit 1
