# Task 09: Output Format System and Shared Formatters

**Story**: 04-projection-engine
**Estimated Complexity**: M (3-5 hours)
**Status**: Pending

---

## Description

Build the output format dispatch system and any shared formatting utilities that are common across multiple projections. This task wires together the `--format` flag with the per-projection formatters and handles the `--output` flag (default file location, `-` for stdout-only).

While individual projection formatters are created in Tasks 4-8, this task creates the shared infrastructure: the format dispatcher, the file writing logic that respects `--output`, and any shared formatting functions (e.g., table rendering for markdown, header rendering for text).

---

## Files to Create

| File | Purpose |
|------|---------|
| `/home/meywd/GlobalContext/lib/formatters.js` | Shared formatting utilities, format dispatch |

---

## Specification / Implementation Details

### Format Dispatch

```javascript
// Format dispatch
async function outputProjection(projection, projectionDef, options) {
  const { format = 'json', output, quiet = false } = options;

  // Always write JSON to the default projection file (unless --output -)
  if (output !== '-') {
    const jsonPath = output || path.join(getProjectionsDir(projection._session_id), projectionDef.outputFile);
    await mkdirp(path.dirname(jsonPath));
    await atomicWrite(jsonPath, JSON.stringify(projection, null, 2));
  }

  // Format for stdout
  const formatter = projectionDef.formatters[format];
  if (!formatter) {
    throw new Error(`Unknown format: ${format}. Supported: json, text, markdown`);
  }

  const output_str = formatter(projection);
  process.stdout.write(output_str);
  if (!output_str.endsWith('\n')) process.stdout.write('\n');
}
```

### Shared Formatting Helpers

- `renderTextHeader(title, subtitle)` -- Title with `===` underline.
- `renderMarkdownTable(headers, rows)` -- Pipe-delimited table with alignment row.
- `mkdirp(dir)` -- Recursive directory creation for projections dir.

---

## Dependencies

- Task 01: Base Path Resolution and Shared Utilities (`/home/meywd/GlobalContext/tasks/04-projection-engine/01-base-path-resolution-and-shared-utilities.md`)
- Task 02: Projection Registry (`/home/meywd/GlobalContext/tasks/04-projection-engine/02-projection-registry.md`)

---

## Acceptance Tests

- `--format json` produces valid, pretty-printed JSON.
- `--format text` produces clean plain text (no JSON structures).
- `--format markdown` produces valid markdown.
- `--output -` does NOT write a file; output goes only to stdout.
- Default output writes the JSON file AND prints formatted output to stdout.
- The projection directory is created if it does not exist.
