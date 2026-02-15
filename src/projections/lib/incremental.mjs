// incremental.mjs -- Incremental rebuild logic.
// Loads existing projections, checks versions, determines event range,
// orchestrates full vs incremental builds.
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { getProjectionsDir } from './paths.mjs';
import { safeJsonParse, warn } from './utils.mjs';
import { replayThrough, getHighestSequence } from './replay.mjs';

/**
 * Load an existing projection file from disk.
 * @returns {object|null}
 */
async function loadExistingProjection(projectId, sessionId, projectionDef) {
  const filePath = path.join(
    getProjectionsDir(projectId, sessionId),
    projectionDef.outputFile
  );
  try {
    const content = await readFile(filePath, 'utf-8');
    const result = safeJsonParse(content, filePath);
    if (!result.ok) {
      warn(`Failed to parse existing projection at ${filePath}: ${result.error}`);
      return null;
    }
    return result.data;
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    warn(`Failed to read existing projection at ${filePath}: ${e.message}`);
    return null;
  }
}

/**
 * Build a projection with incremental rebuild support.
 *
 * @param {string} projectId
 * @param {string} sessionId
 * @param {object} projectionDef - Registry definition { handler, version, outputFile, ... }
 * @param {object} options - { from, to, rebuild }
 * @returns {object} finalized projection
 */
export async function buildProjection(projectId, sessionId, projectionDef, options = {}) {
  const { from, to, rebuild = false } = options;

  let existingProjection = null;
  let startFrom = from || 1;

  if (!rebuild) {
    existingProjection = await loadExistingProjection(projectId, sessionId, projectionDef);

    if (existingProjection) {
      // Version check (M-1): mismatch triggers full rebuild
      if (existingProjection._projection_version !== projectionDef.version) {
        warn(`Projection version mismatch (file: ${existingProjection._projection_version}, ` +
             `current: ${projectionDef.version}). Triggering full rebuild.`);
        existingProjection = null;
      } else {
        startFrom = Math.max(startFrom, (existingProjection._last_sequence || 0) + 1);
      }
    }
  }

  // Check if there are new events to process
  const highestSequence = await getHighestSequence(projectId, sessionId);
  if (existingProjection && startFrom > highestSequence) {
    // No new events -- return existing projection as-is
    return existingProjection;
  }

  // Build or merge
  let result;
  if (existingProjection) {
    // Incremental: initialize handler from existing state
    result = await replayThrough(projectId, sessionId, projectionDef.handler, {
      from: startFrom,
      to,
      existingState: existingProjection,
    });
  } else {
    // Full rebuild
    result = await replayThrough(projectId, sessionId, projectionDef.handler, {
      from: from || 1,
      to,
    });
  }

  // Update metadata
  result._rebuilt_at = new Date().toISOString();
  if (highestSequence > 0) {
    result._last_sequence = to ? Math.min(to, highestSequence) : highestSequence;
  }

  return result;
}
