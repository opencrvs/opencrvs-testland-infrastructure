#!/usr/bin/env node
/*
 * Creates the GitHub App for Mastra Factory with the GitHub App manifest flow,
 * and turns its credentials into the Kubernetes secret "factory-github-app".
 *
 * 1. The script starts a small web server on 127.0.0.1.
 * 2. You open the page that it prints. The page sends the App settings to
 *    GitHub, and you click "Create GitHub App" on GitHub.
 * 3. GitHub sends your browser back to the script with a one-time code.
 * 4. The script exchanges the code for the App credentials and writes the
 *    secret. It does not print the credentials.
 *
 * Usage (from the repository root):
 *   node environments/non-prod/factory/create-github-app.mjs
 *   node environments/non-prod/factory/create-github-app.mjs --apply
 *
 * Without --apply, the script writes the secret to a file (mode 600) that you
 * apply on a machine with access to the cluster. With --apply, it sends the
 * secret to the current kubectl context.
 *
 * You must be an owner or a GitHub App manager of the organization.
 * Do all steps in one hour. After that, the code from GitHub stops working.
 */
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

const { values: options } = parseArgs({
  options: {
    org: { type: 'string', default: 'opencrvs' },
    name: { type: 'string', default: 'OpenCRVS Factory' },
    'public-url': { type: 'string', default: 'https://factory.opencrvs.dev' },
    namespace: { type: 'string', default: 'factory' },
    port: { type: 'string', default: '3591' },
    out: { type: 'string', default: join(homedir(), 'factory-github-app.secret.json') },
    apply: { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
});

if (options.help) {
  console.log(`Options:
  --org <name>          GitHub organization that owns the App (default: opencrvs)
  --name <name>         App name. You can change it on GitHub too. (default: OpenCRVS Factory)
  --public-url <url>    Public URL of Factory (default: https://factory.opencrvs.dev)
  --namespace <name>    Kubernetes namespace of the secret (default: factory)
  --port <number>       Local port for the callback (default: 3591)
  --out <file>          Secret file to write without --apply (default: ~/factory-github-app.secret.json)
  --apply               Send the secret to the current kubectl context instead of a file`);
  process.exit(0);
}

const GITHUB_URL = process.env.GITHUB_SERVER_URL ?? 'https://github.com';
const GITHUB_API_URL = process.env.GITHUB_API_URL ?? 'https://api.github.com';
const ONE_HOUR_MS = 60 * 60 * 1000;

// GitHub gives the credentials one time only. So check before the start that
// the script can save them.
if (existsSync(options.out)) {
  console.error(`${options.out} exists. Move it, or give another path with --out.`);
  process.exit(1);
}
if (options.apply) {
  const context = spawnSync('kubectl', ['config', 'current-context'], { encoding: 'utf8' });
  if (context.status !== 0) {
    console.error('kubectl has no current context. Run without --apply to write the secret to a file.');
    process.exit(1);
  }
  const namespace = spawnSync('kubectl', ['get', 'namespace', options.namespace, '-o', 'name'], { encoding: 'utf8' });
  if (namespace.status !== 0) {
    console.error(`The namespace "${options.namespace}" does not exist in the context "${context.stdout.trim()}". Create it first.`);
    process.exit(1);
  }
  console.log(`kubectl context: ${context.stdout.trim()}`);
}

const publicUrl = options['public-url'].replace(/\/+$/, '');
const localUrl = `http://127.0.0.1:${Number(options.port)}`;
const state = randomBytes(32).toString('hex');

// Factory needs these permissions and events. See
// https://factory.mastra.ai/configure/github. Factory's own integration for
// the Mastra platform also reads checks, statuses and actions, and the review
// skill uses them for `gh pr checks`.
const manifest = {
  name: options.name,
  url: publicUrl,
  description: 'Mastra Factory for OpenCRVS. It turns labelled issues into plans and pull requests.',
  hook_attributes: { url: `${publicUrl}/web/github/webhook`, active: true },
  redirect_url: `${localUrl}/callback`,
  callback_urls: [`${publicUrl}/auth/github/callback`],
  setup_url: `${publicUrl}/auth/github/callback`,
  public: false,
  default_permissions: {
    contents: 'write',
    issues: 'write',
    pull_requests: 'write',
    metadata: 'read',
    checks: 'read',
    statuses: 'read',
    actions: 'read',
  },
  default_events: ['issues', 'issue_comment', 'pull_request', 'pull_request_review', 'pull_request_review_comment'],
};

function escapeHtml(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function page(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 44rem; margin: 3rem auto; padding: 0 1rem; line-height: 1.5; color: #1f2328; background: #fff; }
  code { background: #f6f8fa; padding: 0.1rem 0.3rem; border-radius: 4px; }
  button { font: inherit; padding: 0.6rem 1.2rem; border: 0; border-radius: 6px; background: #1f883d; color: #fff; cursor: pointer; }
  li { margin: 0.2rem 0; }
</style>
</head>
<body>
${body}
</body>
</html>`;
}

function startPage() {
  const action = `${GITHUB_URL}/organizations/${encodeURIComponent(options.org)}/settings/apps/new?state=${state}`;
  const permissions = Object.entries(manifest.default_permissions)
    .map(([name, access]) => `<li><code>${escapeHtml(name)}</code>: ${escapeHtml(access)}</li>`)
    .join('');
  return page(
    'Create the Factory GitHub App',
    `<h1>Create the Factory GitHub App</h1>
<p>This sends the settings below to GitHub. On GitHub, check the name and click <strong>Create GitHub App</strong>. Then GitHub sends you back to this script.</p>
<ul>
  <li>Organization: <code>${escapeHtml(options.org)}</code></li>
  <li>Name: <code>${escapeHtml(manifest.name)}</code></li>
  <li>Webhook URL: <code>${escapeHtml(manifest.hook_attributes.url)}</code></li>
  <li>Callback and setup URL: <code>${escapeHtml(manifest.setup_url)}</code></li>
  <li>Events: ${manifest.default_events.map(event => `<code>${escapeHtml(event)}</code>`).join(', ')}</li>
</ul>
<p>Permissions:</p>
<ul>${permissions}</ul>
<form action="${escapeHtml(action)}" method="post">
  <input type="hidden" name="manifest" value="${escapeHtml(JSON.stringify(manifest))}">
  <button type="submit">Continue to GitHub</button>
</form>`,
  );
}

async function convertCode(code) {
  const response = await fetch(`${GITHUB_API_URL}/app-manifests/${encodeURIComponent(code)}/conversions`, {
    method: 'POST',
    headers: { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
  });
  if (response.status !== 201) {
    throw new Error(`GitHub did not convert the code (HTTP ${response.status}). The code works one time only, and for one hour.`);
  }
  const app = await response.json();
  for (const field of ['id', 'slug', 'client_id', 'client_secret', 'webhook_secret', 'pem']) {
    if (!app[field]) throw new Error(`The response from GitHub has no "${field}".`);
  }
  return app;
}

function secretManifest(app) {
  return {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: { name: 'factory-github-app', namespace: options.namespace },
    type: 'Opaque',
    stringData: {
      GITHUB_APP_ID: String(app.id),
      GITHUB_APP_PRIVATE_KEY: app.pem,
      GITHUB_APP_CLIENT_ID: app.client_id,
      GITHUB_APP_CLIENT_SECRET: app.client_secret,
      GITHUB_APP_SLUG: app.slug,
      GITHUB_APP_WEBHOOK_SECRET: app.webhook_secret,
    },
  };
}

// The secret goes to kubectl through stdin, so it is not in the process list.
function kubectlApply(secret) {
  return new Promise((resolve, reject) => {
    const child = spawn('kubectl', ['apply', '-f', '-'], { stdio: ['pipe', 'inherit', 'inherit'] });
    child.on('error', reject);
    child.on('close', code => (code === 0 ? resolve() : reject(new Error(`kubectl apply exited with ${code}.`))));
    child.stdin.end(JSON.stringify(secret));
  });
}

async function saveSecret(app) {
  const secret = secretManifest(app);
  if (options.apply) {
    try {
      await kubectlApply(secret);
      return `The secret <code>factory-github-app</code> is in the namespace <code>${escapeHtml(options.namespace)}</code>.`;
    } catch (error) {
      // The code from GitHub is used now, so keep the credentials in a file.
      console.error(`\n${error.message} The script writes the secret to a file instead.`);
    }
  }
  // "wx" refuses to replace a file that exists.
  writeFileSync(options.out, `${JSON.stringify(secret, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  console.log(`\nThe secret is in ${options.out} (mode 600). Apply it with:\n  kubectl apply -f ${options.out}\nThen delete the file.`);
  return `The secret is in <code>${escapeHtml(options.out)}</code>. Apply it with <code>kubectl apply -f ${escapeHtml(options.out)}</code>, and then delete the file.`;
}

let finished = false;
const server = createServer(async (request, response) => {
  const url = new URL(request.url ?? '/', localUrl);
  const send = (status, html) => {
    response.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    response.end(html);
  };

  if (request.method === 'GET' && url.pathname === '/') return send(200, startPage());
  if (request.method !== 'GET' || url.pathname !== '/callback') return send(404, page('Not found', '<p>Not found.</p>'));

  if (finished) return send(409, page('Already done', '<p>This script already created the App. Look at the terminal.</p>'));
  if (url.searchParams.get('state') !== state) {
    return send(400, page('Wrong state', '<p>The state from GitHub is wrong. Start again from the page that the script printed.</p>'));
  }
  const code = url.searchParams.get('code');
  if (!code) return send(400, page('No code', '<p>GitHub did not send a code.</p>'));

  finished = true;
  try {
    const app = await convertCode(code);
    const where = await saveSecret(app);
    const installUrl = `${GITHUB_URL}/apps/${encodeURIComponent(app.slug)}/installations/new`;
    console.log(`\nGitHub App created: ${app.slug} (ID ${app.id}).`);
    console.log(`Next, install it on opencrvs-core only: ${installUrl}`);
    send(
      200,
      page(
        'GitHub App created',
        `<h1>GitHub App created</h1>
<p>The App <code>${escapeHtml(app.slug)}</code> (ID ${escapeHtml(app.id)}) exists now. ${where}</p>
<p>Next, <a href="${escapeHtml(installUrl)}">install the App</a> on <code>opencrvs-core</code> only.</p>
<p>You can close this page.</p>`,
      ),
    );
    server.close();
  } catch (error) {
    console.error(`\n${error.message}`);
    process.exitCode = 1;
    send(500, page('Failed', `<h1>Failed</h1><p>${escapeHtml(error.message)}</p><p>Look at the terminal.</p>`));
    server.close();
  }
});

server.listen(Number(options.port), '127.0.0.1', () => {
  console.log(`Open this page in your browser and follow it:\n  ${localUrl}/\n`);
  console.log(options.apply ? 'The secret will go to the current kubectl context.' : `The secret will go to ${options.out}.`);
});

setTimeout(() => {
  if (finished) return;
  console.error('\nStopped after one hour. The code from GitHub works for one hour only, so start again.');
  process.exit(1);
}, ONE_HOUR_MS).unref();
