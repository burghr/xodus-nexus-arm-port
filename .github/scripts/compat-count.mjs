// Counts the game reports that the arm64 launcher sends as issues, and writes
// compat.json to the compat-data branch. The launcher reads that file.
// Issue text comes from any GitHub user: only parse it, never run it.
import { readFile } from 'node:fs/promises';

const MARKER = /<!-- nexus-compat (\{[^\n]*\}) -->/;
const LABEL = 'game report';
const BRANCH = 'compat-data';
const FILE = 'compat.json';
const STORE_ID = /^[0-9A-Z]{12}$/;

const clean = (value, limit) => typeof value === 'string' ? value.replace(/[\p{C}<>`]/gu, '').trim().slice(0, limit) : '';

/** Returns the report in an issue body, or undefined when the body has none or a bad one. */
export function parseReport(body) {
  const match = MARKER.exec(body ?? '');
  if (!match) return undefined;
  let data;
  try { data = JSON.parse(match[1]); } catch { return undefined; }
  if (!data || !STORE_ID.test(data.storeId) || typeof data.works !== 'boolean') return undefined;
  const launcher = clean(data.launcher, 40);
  if (!/^\d+\.\d+\.\d+(-arm\.\d+)?$/.test(launcher)) return undefined;
  return { storeId: data.storeId, title: clean(data.title, 120) || data.storeId, works: data.works, launcher };
}

export function compareVersions(a, b) {
  const parts = value => value.match(/\d+/g).map(Number);
  const left = parts(a), right = parts(b);
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference) return difference;
  }
  return 0;
}

/** One vote for each user, game and launcher version: the newest report wins. */
export function countReports(issues) {
  const votes = new Map();
  for (const issue of [...issues].sort((a, b) => a.created_at.localeCompare(b.created_at))) {
    if (issue.pull_request || issue.state_reason === 'not_planned' || issue.labels.some(label => (label.name ?? label) === 'invalid')) continue;
    const report = parseReport(issue.body);
    if (report) votes.set(`${report.storeId}|${issue.user.login.toLowerCase()}|${report.launcher}`, { ...report, issue: issue.number });
  }
  const games = {};
  for (const vote of votes.values()) {
    const game = games[vote.storeId] ??= { title: vote.title, launcher: vote.launcher, works: 0, broken: 0, total: 0, issues: [] };
    game.total += 1;
    game.title = vote.title;
    if (compareVersions(vote.launcher, game.launcher) > 0) Object.assign(game, { launcher: vote.launcher, works: 0, broken: 0, issues: [] });
    if (vote.launcher !== game.launcher) continue;
    vote.works ? game.works += 1 : game.broken += 1;
    game.issues.push(vote.issue);
  }
  for (const game of Object.values(games)) {
    game.status = game.works > game.broken ? 'playable' : game.broken > game.works ? 'not-playable' : 'mixed';
    game.issues.sort((a, b) => a - b);
  }
  return Object.fromEntries(Object.entries(games).sort(([, a], [, b]) => a.title.localeCompare(b.title)));
}

async function github(path, init = {}) {
  const response = await fetch(`https://api.github.com${path}`, { ...init, headers: {
    Accept: 'application/vnd.github+json', Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, 'X-GitHub-Api-Version': '2022-11-28', ...init.headers,
  } });
  if (response.status === 404 && init.allow404) return undefined;
  if (!response.ok) throw Error(`${init.method ?? 'GET'} ${path}: HTTP ${response.status} ${await response.text()}`);
  return response.status === 204 ? undefined : response.json();
}

async function main() {
  const repo = process.env.GITHUB_REPOSITORY;
  const event = process.env.GITHUB_EVENT_PATH ? JSON.parse(await readFile(process.env.GITHUB_EVENT_PATH, 'utf8')) : {};
  const issue = event.issue;
  // A new launcher report gets the label and is closed at once, so that the open issues show only real problems.
  if (issue && ['opened', 'edited', 'reopened'].includes(event.action) && parseReport(issue.body)) {
    if (!issue.labels.some(label => label.name === LABEL)) await github(`/repos/${repo}/issues/${issue.number}/labels`, { method: 'POST', body: JSON.stringify({ labels: [LABEL] }) });
    if (issue.state === 'open' && event.action === 'opened') await github(`/repos/${repo}/issues/${issue.number}`, { method: 'PATCH', body: JSON.stringify({ state: 'closed', state_reason: 'completed' }) });
  }
  const issues = [];
  for (let page = 1; ; page += 1) {
    const batch = await github(`/repos/${repo}/issues?state=all&labels=${encodeURIComponent(LABEL)}&per_page=100&page=${page}`);
    issues.push(...batch);
    if (batch.length < 100) break;
  }
  const games = countReports(issues);
  const content = JSON.stringify({ schema: 1, games }, null, 2) + '\n';
  const current = await github(`/repos/${repo}/contents/${FILE}?ref=${BRANCH}`, { allow404: true });
  if (current && Buffer.from(current.content, 'base64').toString('utf8') === content) { console.log('compat.json is current.'); return; }
  await github(`/repos/${repo}/contents/${FILE}`, { method: 'PUT', body: JSON.stringify({
    message: `Update compat.json (${Object.keys(games).length} games)`, content: Buffer.from(content).toString('base64'), branch: BRANCH, sha: current?.sha,
  }) });
  console.log(`compat.json now has ${Object.keys(games).length} games.`);
}

if (import.meta.url === `file://${process.argv[1]}`) await main();
