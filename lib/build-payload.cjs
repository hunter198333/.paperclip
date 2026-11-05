#!/usr/bin/env node
/**
 * build-payload — turn .paperclip/business.config.json into the exact JSON bodies
 * the Paperclip CLI expects. No jq required, and $BUSINESS_ROOT gets expanded to a
 * real absolute path (Paperclip rejects relative cwd values).
 *
 *   node lib/build-payload.cjs company
 *   node lib/build-payload.cjs goal      offer
 *   node lib/build-payload.cjs project   core [goalId1,goalId2]
 *   node lib/build-payload.cjs workspace core
 *   node lib/build-payload.cjs agent     builder
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const BUSINESS_ROOT = (process.env.BUSINESS_ROOT || ROOT).replace(/\/+$/, '');
const CFG = JSON.parse(fs.readFileSync(path.join(ROOT, '.paperclip', 'business.config.json'), 'utf8'));

function expand(value) {
  if (typeof value === 'string') {
    return value.replace(/\$BUSINESS_ROOT/g, BUSINESS_ROOT).replace(/^~(?=\/)/, process.env.HOME || '~');
  }
  if (Array.isArray(value)) return value.map(expand);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = expand(v);
    return out;
  }
  return value;
}

const [kind, key, extra] = process.argv.slice(2);
if (!kind) {
  process.stderr.write('usage: build-payload.cjs <company|goal|project|workspace|agent> [key] [extra]\n');
  process.exit(1);
}

let body = null;

if (kind === 'company') {
  const c = CFG.company;
  body = {
    name: c.name,
    issuePrefix: c.issuePrefix,
    description: c.description,
  };
  if (c.budgetMonthlyCents) body.budgetMonthlyCents = c.budgetMonthlyCents;
  if (c.requiresAgentApproval) body.requiresAgentApproval = true;
} else if (kind === 'goal') {
  const g = CFG.goals.find((x) => x.key === key);
  if (!g) { process.stderr.write(`no goal with key "${key}"\n`); process.exit(1); }
  body = { title: g.title, description: g.description, level: g.level, status: g.status };
} else if (kind === 'project') {
  const p = CFG.projects.find((x) => x.key === key);
  if (!p) { process.stderr.write(`no project with key "${key}"\n`); process.exit(1); }
  body = {
    name: p.name,
    description: p.description,
    status: p.status,
    executionWorkspacePolicy: p.executionWorkspacePolicy,
  };
  if (extra) body.goalIds = extra.split(',').filter(Boolean);
} else if (kind === 'workspace') {
  const w = CFG.workspaces.find((x) => x.key === key);
  if (!w) { process.stderr.write(`no workspace with key "${key}"\n`); process.exit(1); }
  body = { name: w.name, cwd: expand(w.cwd), repoRef: w.repoRef, isPrimary: w.isPrimary };
  if (w.repoUrl) body.repoUrl = w.repoUrl;
} else if (kind === 'agent') {
  const a = CFG.agents.find((x) => x.key === key);
  if (!a) { process.stderr.write(`no agent with key "${key}"\n`); process.exit(1); }
  const file = path.join(ROOT, a.configFile);
  const local = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
  body = {
    name: a.name,
    title: a.title,
    adapterType: local.adapterType || a.adapterType || CFG.paperclip.adapterTypeDefault,
  };
  const ac = expand(local.adapterConfig || {});
  if (ac.cwd) body.adapterConfig = ac;
  else body.adapterConfig = { cwd: expand(`${BUSINESS_ROOT}/workspaces/${a.workspaceKey}`) };
} else {
  process.stderr.write(`unknown kind "${kind}"\n`);
  process.exit(1);
}

process.stdout.write(JSON.stringify(body));
