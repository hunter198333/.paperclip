#!/usr/bin/env node
/**
 * find-by-title — resolve an id by matching a display name.
 *
 *   pc agent list --company-id $CID --json | node lib/find-by-title.cjs "Builder"
 *   pc goal  list --company-id $CID --json | node lib/find-by-title.cjs "Ship a working offer" title
 *
 * Handles both a bare array and {items:[...]} / {data:[...]} / {agents:[...]} envelopes.
 * Prints the id, or nothing (exit 0) if there is no match.
 */
let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  const needle = (process.argv[2] || '').toLowerCase();
  const fields = process.argv[3] ? [process.argv[3]] : ['title', 'name'];
  let j;
  try {
    j = JSON.parse(raw);
  } catch (e) {
    process.exit(0);
  }
  let items = [];
  if (Array.isArray(j)) items = j;
  else if (j && typeof j === 'object') {
    for (const k of ['items', 'data', 'agents', 'goals', 'projects', 'workspaces', 'issues', 'companies']) {
      if (Array.isArray(j[k])) { items = j[k]; break; }
    }
  }
  const hit = items.find((it) => {
    if (!it || typeof it !== 'object') return false;
    return fields.some((f) => typeof it[f] === 'string' && it[f].toLowerCase() === needle);
  });
  if (hit && hit.id) process.stdout.write(String(hit.id));
});
