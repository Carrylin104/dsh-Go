import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { mkdtemp, mkdir, realpath, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CATALOG, Config, HARD_LIMITS, catalogModel, runtimeSnapshot } from '../src/config.js';
import { createMediaClient, createDescriptor, normalizeTask, providerEndpoint } from '../src/adapters.js';
import { parseMediaUrl, createHttpTransport } from '../src/http.js';
import { mediaDownloadOptions, museApiRoot } from '../src/muse.js';
import { generateMedia } from '../src/media-engine.js';
import { admitGeneration, recoverAdmission } from '../src/budget.js';
import { selectedRequest } from '../src/index.js';

const KEY = 'synthetic-muse-key-for-tests-only';
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ6sAAAAASUVORK5CYII=', 'base64');
const MP4 = Buffer.from((await readFile(new URL('./fixtures/video.base64', import.meta.url), 'utf8')).trim(), 'base64');
const request = (kind, baseUrl) => ({ prompt: '一只猫', n: 1, refs: [], aspect: '9:16',
  service: { id: 'muse_' + kind, provider: 'muse2api', profile: 'muse-' + kind, baseUrl }, model: catalogModel('muse-' + kind) });

async function gateway(t, { drop = false, state = 'completed' } = {}) {
  const wires = [];
  let queries = 0;
  const server = createServer(async (req, res) => {
    let body = '';
    for await (const chunk of req) body += chunk;
    wires.push({ method: req.method, path: req.url, auth: req.headers.authorization, body: body ? JSON.parse(body) : undefined });
    if (req.headers.authorization !== 'Bearer ' + KEY) { res.writeHead(401); res.end('{}'); return; }
    if (req.method === 'POST') {
      if (drop) { req.socket.destroy(); return; }
      res.writeHead(202); res.end(JSON.stringify({ id: 'task-1', status: 'pending' })); return;
    }
    if (req.url.startsWith('/v1/media/')) {
      res.end(req.url.endsWith('.mp4') ? MP4 : PNG); return;
    }
    const video = req.url.startsWith('/v1/videos/');
    const currentState = ++queries === 1 ? 'processing' : state;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ id: 'task-1', status: currentState,
      ...(currentState === 'failed' ? { error: 'private provider detail must not become public' }
        : video ? { result: { url: '/v1/media/original.mp4' } } : { data: [{ url: '/v1/media/original.png' }] }) }));
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(async () => { server.closeAllConnections(); await new Promise(done => server.close(done)); });
  return { wires, origin: `http://127.0.0.1:${server.address().port}` };
}

test('Muse image interrupted after receipt resumes by GET with the original task identity', { skip: process.platform === 'win32' }, async t => {
  const f = await gateway(t), req = request('image', f.origin);
  const directory = await realpath(await mkdtemp(join(tmpdir(), 'muse-resume-')));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const workspace = join(directory, 'workspace'); await mkdir(workspace);
  const controller = new AbortController();
  const context = { signal: controller.signal, sessionId: 'resume-session', keyRef: 'MUSE_KEY', hostStateDir: join(directory, 'host'),
    limits: HARD_LIMITS, pollMs: 1, budget: { dailyMicros: 20_000_000, unknownHoldMicros: 20_000_000 }, approve: async () => 'allowed-once',
    authorizeWorkspace: async () => ({ cwd: workspace, workspaceRoot: workspace, mode: 'workspace-write' }), resolveCredential: async () => KEY,
    job: { id: 'first-job', updateProgress(text) { if (text === '图片正在生成') controller.abort(); } } };
  context.admission = await admitGeneration(req, context);
  await assert.rejects(generateMedia(req, context), { code: 'remote_may_continue' });
  const resumedContext = { ...context, signal: new AbortController().signal, job: undefined };
  const saved = await recoverAdmission(context.admission.rid, resumedContext);
  assert.equal(saved.providerTaskId, 'task-1');
  const result = await generateMedia(saved.request, { ...resumedContext, admission: saved.admission, resumeTaskId: saved.providerTaskId });
  assert.equal(result.meta.rid, context.admission.rid);
  assert.deepEqual(await readFile(result.meta.items[0].path), PNG);
  assert.equal(f.wires.filter(row => row.method === 'POST').length, 1);
});

test('Muse presets configure both tools with one credential and exact supported parameters', () => {
  const services = ['image', 'video'].map(kind => ({ ...request(kind, 'http://192.168.1.10:18610/v1').service,
    enabled: true, models: 'muse-' + kind, keyRef: 'MUSE_KEY' }));
  const snapshot = runtimeSnapshot(Config({ services }));
  for (const kind of ['image', 'video']) {
    const selected = selectedRequest({ prompt: '猫', aspect: '9:16', ...(kind === 'video' ? { seconds: 8 } : {}) }, snapshot, snapshot.services, 'generate_' + kind);
    const wire = createDescriptor(selected.request, kind === 'video' ? ['data:image/png;base64,abc'] : []);
    assert.equal(wire.path, kind === 'video' ? '/videos' : '/images/tasks');
    assert.equal(wire.body.size, '9:16');
    if (kind === 'video') { assert.equal(wire.body.duration, 8); assert.deepEqual(wire.body.images, [{ url: 'data:image/png;base64,abc' }]); }
    assert.equal(selected.keyRef, 'MUSE_KEY');
  }
  const image = request('image', services[0].baseUrl);
  assert.deepEqual(createDescriptor(image, ['reference-data']).body.images, [{ url: 'reference-data' }]);
  assert.throws(() => selectedRequest({ prompt: '猫', n: 2 }, snapshot, snapshot.services), { code: 'invalid_request' });
});

test('Muse roots normalize /v1 once; admin pages, credentials and URL parameters are refused', () => {
  const service = request('image', 'http://192.168.1.10:18610').service;
  assert.equal(providerEndpoint(service, '/images/tasks'), 'http://192.168.1.10:18610/v1/images/tasks');
  service.baseUrl += '/v1/';
  assert.equal(providerEndpoint(service, '/images/tasks'), 'http://192.168.1.10:18610/v1/images/tasks');
  assert.equal(museApiRoot('https://gateway.example/muse/v1/'), 'https://gateway.example/muse/v1');
  for (const value of ['ftp://host/v1', 'http://u:p@host/v1', 'http://host/admin', 'http://host/v1/videos', 'http://host/v1?key=secret', 'http://host/v1#x']) {
    assert.throws(() => museApiRoot(value), { code: 'unsafe_url' });
  }
});

for (const kind of ['image', 'video']) {
  test(`real HTTP Muse ${kind}: submit once, poll processing/completed and authenticate local media`, async t => {
    const f = await gateway(t), req = request(kind, f.origin + '/v1');
    const client = createMediaClient();
    const created = await client.create(req, [], KEY);
    assert.equal(created.taskId, 'task-1');
    assert.equal((await client.query(req, created.taskId, KEY)).state, 'running');
    const completed = await client.query(req, created.taskId, KEY);
    assert.equal(completed.state, 'succeeded');
    const url = completed.images?.[0].url ?? completed.url;
    const options = mediaDownloadOptions(url, req.service, KEY);
    const result = await createHttpTransport()(url, { ...options, maxBytes: 100_000 });
    assert.deepEqual(result.body, kind === 'image' ? PNG : MP4);
    assert.equal(f.wires.filter(row => row.method === 'POST').length, 1);
    assert.ok(f.wires.every(row => row.auth === 'Bearer ' + KEY));
    assert.equal(await client.cancel(req, created.taskId, KEY), 'unsupported');
    assert.equal(f.wires.length, 4);
  });
}

test('a lost POST response is never retried', async t => {
  const f = await gateway(t, { drop: true });
  await assert.rejects(createMediaClient().create(request('image', f.origin), [], KEY), { code: 'submission_unknown' });
  assert.equal(f.wires.length, 1);
});

test('matching failed Muse receipts remain terminal failures and do not expose provider error text', async t => {
  const f = await gateway(t, { state: 'failed' }), req = request('video', f.origin);
  const client = createMediaClient();
  await client.query(req, 'task-1', KEY);
  assert.deepEqual(await client.query(req, 'task-1', KEY), { taskId: 'task-1', state: 'failed' });
  assert.throws(() => normalizeTask('muse-video', { id: 'other', status: 'failed' }, 'task-1'), { code: 'response' });
});

test('Muse trust and auth are scoped to the configured origin, including image redirect hops', () => {
  const service = request('image', 'http://192.168.1.10:18610/v1').service;
  assert.equal(mediaDownloadOptions('http://192.168.1.10:18610/v1/media/a.png', service, KEY).headers.authorization, 'Bearer ' + KEY);
  assert.deepEqual(mediaDownloadOptions('https://cdn.example/a.png', service, KEY), {});
  for (const url of ['http://192.168.1.11:18610/a.png', 'http://192.168.1.10:18611/a.png', 'https://127.0.0.1/a.png']) {
    assert.throws(() => mediaDownloadOptions(url, service, KEY), { code: 'unsafe_url' });
  }
  assert.throws(() => parseMediaUrl(service.baseUrl), { code: 'unsafe_url' });
  assert.deepEqual(mediaDownloadOptions('https://cdn.example/a.png', { profile: 'ark-image' }, KEY), {});
});

// Publication fsync is a Linux/Android contract. Windows cannot supply it.
for (const kind of ['image', 'video']) {
  test(`Muse ${kind} engine: original bytes, media card and restart recovery without another POST`, { skip: process.platform === 'win32' }, async t => {
    const f = await gateway(t), req = request(kind, f.origin);
    const directory = await realpath(await mkdtemp(join(tmpdir(), 'muse-engine-')));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const workspace = join(directory, 'workspace'); await mkdir(workspace);
    const context = { signal: new AbortController().signal, sessionId: 'muse-session', keyRef: 'MUSE_KEY', hostStateDir: join(directory, 'host'),
      limits: HARD_LIMITS, pollMs: 1, budget: { dailyMicros: 20_000_000, unknownHoldMicros: 20_000_000 }, approve: async () => 'allowed-once',
      authorizeWorkspace: async () => ({ cwd: workspace, workspaceRoot: workspace, mode: 'workspace-write' }), resolveCredential: async () => KEY };
    context.admission = await admitGeneration(req, context);
    const result = await generateMedia(req, context);
    assert.equal(result.meta.kind, kind); assert.equal(result.meta.status, 'done');
    assert.equal(result.meta.items.length, 1);
    assert.deepEqual(await readFile(result.meta.items[0].path), kind === 'image' ? PNG : MP4);
    assert.equal(JSON.stringify(result).includes(KEY), false);
    const saved = await recoverAdmission(context.admission.rid, context);
    assert.deepEqual(saved.completed.meta, result.meta);
    assert.equal(f.wires.filter(row => row.method === 'POST').length, 1);
  });
}
