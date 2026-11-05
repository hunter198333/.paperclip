#!/usr/bin/env node
/**
 * jqlite — a tiny jq replacement, so you don't need jq installed.
 *
 *   pc company list --json | node lib/jqlite.cjs 'j[0].id'
 *   pc issue list --json  | node lib/jqlite.cjs 'j.filter(i=>i.status==="todo").length'
 *
 * The expression is evaluated with `j` bound to the parsed JSON.
 */
let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  let j;
  try {
    j = JSON.parse(raw);
  } catch (e) {
    process.stderr.write('jqlite: input is not valid JSON\n');
    process.exit(1);
  }
  const expr = process.argv[2];
  if (!expr) {
    process.stderr.write('usage: jqlite.cjs <expr>\n');
    process.exit(1);
  }
  let v;
  try {
    v = new Function('j', `return (${expr});`)(j);
  } catch (e) {
    process.stderr.write(`jqlite: ${e.message}\n`);
    process.exit(1);
  }
  if (v === undefined || v === null) process.exit(0);
  process.stdout.write(typeof v === 'object' ? JSON.stringify(v) : String(v));
});
