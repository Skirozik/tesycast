// End-to-end checks for the Tesycast Worker. Runs against `wrangler dev` by
// default, or any deployment: BASE=https://tesycast.com node test/e2e.mjs
// Needs Node 22+ (global WebSocket and fetch).
const BASE = process.env.BASE || 'http://127.0.0.1:8787';
const WSB = BASE.replace(/^http/, 'ws');
const LIVEKIT_URL = process.env.LIVEKIT_WS_URL || 'wss://tesycast-85onreo6.livekit.cloud';

let pass = 0, fail = 0;
const results = [];
function check(name, ok, extra = '') {
  if (ok) { pass++; results.push(`  PASS  ${name}`); }
  else { fail++; results.push(`  FAIL  ${name} ${extra}`); }
}
const rnd = n => Array.from({ length: n }, () => 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]).join('');
const sleep = ms => new Promise(r => setTimeout(r, ms));

function decodeJwt(t) {
  const p = t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
  return JSON.parse(Buffer.from(p, 'base64').toString());
}

// `onmessage` is attached before the socket opens, so a frame the relay sends
// the moment a viewer joins (join replay) is never missed.
function openWs(url, { binary = false, onmessage = null } = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    if (binary) ws.binaryType = 'arraybuffer';
    if (onmessage) ws.onmessage = onmessage;
    ws.onopen = () => resolve({ ws });
    ws.onclose = e => resolve({ ws, closeEvent: e });
    ws.onerror = () => {};
    setTimeout(() => reject(new Error('ws timeout ' + url)), 5000);
  });
}
const waitClose = ws => new Promise(res => {
  ws.addEventListener('close', e => res(e));
  setTimeout(() => res({ code: null }), 3000);
});

// ── Stateless routes ────────────────────────────────────────────────────────
{
  const r = await fetch(BASE + '/');
  const body = await r.text();
  check('GET / -> 200 hub html', r.status === 200 && body.includes('Tesycast') && body.includes('github.com/Skirozik'), `status=${r.status}`);
  check('GET / content-type html', (r.headers.get('content-type') || '').includes('text/html'));

  const h = await fetch(BASE + '/healthz');
  check('GET /healthz -> ok', h.status === 200 && (await h.text()) === 'ok');

  const nf = await fetch(BASE + '/nope');
  check('GET /nope -> 404 Not found', nf.status === 404 && (await nf.text()) === 'Not found');

  const bad = await fetch(BASE + '/watch/sh', { redirect: 'manual' });
  check('GET /watch/<too-short> -> 404 (CODE_RE)', bad.status === 404, `status=${bad.status}`);

  const put = await fetch(BASE + '/', { method: 'PUT' });
  check('PUT / -> 405', put.status === 405, `status=${put.status}`);

  const postUnknown = await fetch(BASE + '/whatever', { method: 'POST' });
  check('POST /whatever -> 404', postUnknown.status === 404, `status=${postUnknown.status}`);
}

// ── Tokens + trust-on-first-use ─────────────────────────────────────────────
const code = 'tc' + rnd(10);
const SECRET = 's3cr3t-' + rnd(8);
{
  const r = await fetch(`${BASE}/token/${code}`);
  const j = await r.json();
  check('GET /token subscribe -> 200 json', r.status === 200 && !!j.token, `status=${r.status}`);
  check('subscribe wsUrl is LiveKit Cloud', j.wsUrl === LIVEKIT_URL, `wsUrl=${j.wsUrl}`);
  const claims = decodeJwt(j.token);
  check('subscribe token cannot publish', claims.video.canPublish === false && claims.video.canSubscribe === true, JSON.stringify(claims.video));
  check('subscribe token scoped to room', claims.video.room === code && claims.video.roomJoin === true);
  check('subscribe token canPublishData false', claims.video.canPublishData === false);
  check('subscribe identity prefix sub-', String(claims.sub).startsWith('sub-' + code));

  const noSecret = await fetch(`${BASE}/token/${code}?role=publish`);
  check('publish token w/o secret -> 400', noSecret.status === 400 && (await noSecret.text()) === 'secret required', `status=${noSecret.status}`);

  const claim = await fetch(`${BASE}/token/${code}?role=publish&secret=${SECRET}`);
  const cj = await claim.json();
  check('publish token w/ secret -> 200 (claims code)', claim.status === 200 && !!cj.token, `status=${claim.status}`);
  const pc = decodeJwt(cj.token);
  check('publish token canPublish true', pc.video.canPublish === true && pc.video.canSubscribe === false);
  check('publish identity prefix pub-', String(pc.sub).startsWith('pub-' + code));

  const wrong = await fetch(`${BASE}/token/${code}?role=publish&secret=WRONG`);
  check('publish token wrong secret -> 403', wrong.status === 403, `status=${wrong.status}`);

  const stillOk = await fetch(`${BASE}/token/${code}?role=publish&secret=${SECRET}`);
  check('publish token right secret still works', stillOk.status === 200, `status=${stillOk.status}`);
}

// ── /mode + /watch player selection ─────────────────────────────────────────
{
  const wd = await (await fetch(`${BASE}/watch/${code}`)).text();
  check('GET /watch default -> MJPEG canvas player', wd.includes("'/view/'") && wd.includes('canvas'), '');
  const lk = await (await fetch(`${BASE}/watch/${code}?mode=webrtc`)).text();
  check('GET /watch?mode=webrtc -> LiveKit player', lk.includes('livekit-client') && lk.includes('Connecting'), '');
  check('LiveKit page arms fallback outside the module script', lk.indexOf('var fb=setTimeout') > 0 && lk.indexOf('var fb=setTimeout') < lk.indexOf('type="module"'), '');

  const m = await fetch(`${BASE}/mode/${code}?mode=mjpeg&secret=${SECRET}`, { method: 'POST' });
  check('POST /mode mjpeg -> {"mode":"mjpeg"}', m.status === 200 && (await m.text()) === '{"mode":"mjpeg"}', `status=${m.status}`);

  const mWrong = await fetch(`${BASE}/mode/${code}?mode=webrtc&secret=NOPE`, { method: 'POST' });
  check('POST /mode wrong secret -> 403', mWrong.status === 403, `status=${mWrong.status}`);

  const wm = await (await fetch(`${BASE}/watch/${code}`)).text();
  check('GET /watch after mode=mjpeg -> MJPEG player', wm.includes("'/view/'") && wm.includes('canvas'), '');
  check('MJPEG player ignores string control frames', wm.includes("typeof e.data==='string'"), '');
  check('MJPEG player sends keepalive ping', wm.includes("ws.send('ping')"), '');
  check('MJPEG player acks every 4th received frame', wm.includes("recv%4===0") && wm.includes("ws.send('ack')") && !wm.includes('drawn'), '');
  check('MJPEG player announces received-frame acks (?acks=recv)', wm.includes("'/view/'+code+'?acks=recv'"), '');
  check('MJPEG player decodes via createImageBitmap w/ Image fallback', wm.includes('createImageBitmap(blob)') && wm.includes('new Image()'), '');
  check('MJPEG player uses an opaque canvas', wm.includes("getContext('2d',{alpha:false})"), '');
  check('MJPEG player handles publisher-gone', wm.includes("'publisher-gone'"), '');

  const mw = await fetch(`${BASE}/mode/${code}?mode=webrtc&secret=${SECRET}`, { method: 'POST' });
  check('POST /mode webrtc -> {"mode":"webrtc"}', (await mw.text()) === '{"mode":"webrtc"}');
  check('GET /watch after mode=webrtc -> LiveKit player', (await (await fetch(`${BASE}/watch/${code}`)).text()).includes('livekit-client'));
  check('GET /watch?mode=mjpeg overrides stored mode', (await (await fetch(`${BASE}/watch/${code}?mode=mjpeg`)).text()).includes("'/view/'"));

  const fresh = 'tc' + rnd(10);
  const emptySecret = await fetch(`${BASE}/mode/${fresh}?mode=mjpeg&secret=`, { method: 'POST' });
  check('POST /mode empty secret on fresh code -> 403 (hardened)', emptySecret.status === 403, `status=${emptySecret.status}`);
  const afterEmpty = await fetch(`${BASE}/token/${fresh}?role=publish&secret=legit-owner`);
  check('legit publisher can still claim after empty-secret attempt', afterEmpty.status === 200, `status=${afterEmpty.status}`);
}

// ── /status ─────────────────────────────────────────────────────────────────
{
  const s = await fetch(`${BASE}/status/${code}`);
  check('GET /status -> publisher false, viewers 0', (await s.text()) === '{"publisher":false,"viewers":0}');
  const sNew = await fetch(`${BASE}/status/${'tc' + rnd(10)}`);
  check('GET /status unknown code -> zeros', (await sNew.text()) === '{"publisher":false,"viewers":0}');
}

// ── WebSocket relay ─────────────────────────────────────────────────────────
{
  const noSec = await openWs(`${WSB}/ingest/${code}`);
  const ev1 = await waitClose(noSec.ws);
  check('WS /ingest w/o secret -> close 4001', ev1.code === 4001, `code=${ev1.code}`);

  const badSec = await openWs(`${WSB}/ingest/${code}?secret=WRONG`);
  const ev2 = await waitClose(badSec.ws);
  check('WS /ingest bad secret -> close 4003', ev2.code === 4003, `code=${ev2.code}`);

  const unknown = await openWs(`${WSB}/bogus/${code}`);
  const ev3 = await waitClose(unknown.ws);
  check('WS unknown path -> close 4004', ev3.code === 4004, `code=${ev3.code}`);

  const viewer = await openWs(`${WSB}/view/${code}`, { binary: true });
  const frames = [];
  viewer.ws.onmessage = e => frames.push(e.data);
  const pub = await openWs(`${WSB}/ingest/${code}?secret=${SECRET}`);
  await sleep(300);

  const st = await (await fetch(`${BASE}/status/${code}`)).json();
  check('/status reflects live publisher + viewer', st.publisher === true && st.viewers === 1, JSON.stringify(st));
  check('publisher connect sets mode=mjpeg (was webrtc)', (await (await fetch(`${BASE}/watch/${code}`)).text()).includes("'/view/'"));

  pub.ws.send(new Uint8Array([1, 2, 3, 4, 5]));
  await sleep(400);
  const got = frames.filter(f => f instanceof ArrayBuffer);
  check('publisher frame fans out to viewer', got.length === 1 && new Uint8Array(got[0]).join() === '1,2,3,4,5', `frames=${frames.length}`);

  const f2 = [];
  const viewer2 = await openWs(`${WSB}/view/${code}`, { binary: true, onmessage: e => { if (e.data instanceof ArrayBuffer) f2.push(e.data); } });
  await sleep(300);
  check('late-joining viewer is handed the latest frame', f2.length === 1 && new Uint8Array(f2[0]).join() === '1,2,3,4,5', `got=${f2.length}`);
  viewer.ws.send(new Uint8Array([9, 9, 9]));
  await sleep(400);
  check('viewer cannot inject frames to other viewers', f2.length === 1, `got=${f2.length}`);

  const pongs = [];
  viewer2.ws.onmessage = e => { if (typeof e.data === 'string') pongs.push(e.data); };
  viewer2.ws.send('ping');
  await sleep(400);
  check('keepalive ping -> pong auto-response', pongs.includes('pong'), `got=${JSON.stringify(pongs)}`);

  const pub2 = await openWs(`${WSB}/ingest/${code}?secret=${SECRET}`);
  const replaced = await waitClose(pub.ws);
  check('second publisher replaces first (close 4000)', replaced.code === 4000, `code=${replaced.code}`);

  pub2.ws.close(); viewer.ws.close(); viewer2.ws.close();
  await sleep(400);
}

// ── Claim survives anonymous viewer churn (the hijack finding) ──────────────
{
  const victim = 'tc' + rnd(10);
  const victimSecret = 'owner-' + rnd(8);
  const claimed = await fetch(`${BASE}/token/${victim}?role=publish&secret=${victimSecret}`);
  check('victim claims code', claimed.status === 200);

  const atk = await openWs(`${WSB}/view/${victim}`);
  atk.ws.close();
  await sleep(600);

  const hijack = await fetch(`${BASE}/token/${victim}?role=publish&secret=attacker-secret`);
  check('attacker CANNOT re-claim after viewer churn -> 403', hijack.status === 403, `status=${hijack.status}`);
  const ownerStill = await fetch(`${BASE}/token/${victim}?role=publish&secret=${victimSecret}`);
  check('owner keeps the claim after viewer churn', ownerStill.status === 200, `status=${ownerStill.status}`);
}

// ── Backpressure, publisher-gone, mode persistence ──────────────────────────
{
  const bcode = 'tc' + rnd(10);
  const bsecret = 'bp-' + rnd(8);
  await fetch(`${BASE}/token/${bcode}?role=publish&secret=${bsecret}`);

  const viewer = await openWs(`${WSB}/view/${bcode}`, { binary: true });
  const got = [], texts = [];
  viewer.ws.onmessage = e => { if (typeof e.data === 'string') texts.push(e.data); else got.push(new Uint8Array(e.data)[0]); };
  const pub = await openWs(`${WSB}/ingest/${bcode}?secret=${bsecret}`);
  await sleep(300);

  // The viewer joined before any frame, so there is no join replay here. These
  // sleeps stay well under the 2 s stall refill.
  for (let i = 1; i <= 12; i++) pub.ws.send(new Uint8Array([i, 0, 0]));
  await sleep(400);
  check('viewer without acks receives exactly the 8-frame window', got.join() === '1,2,3,4,5,6,7,8', `got=${got.join()}`);

  viewer.ws.send('ack');
  await sleep(400);
  check('ack hands the behind viewer the freshest frame only', got.length === 9 && got[8] === 12, `got=${got.join()}`);

  pub.ws.send(new Uint8Array([13, 0, 0]));
  await sleep(300);
  check('frames flow again after ack', got.length === 10 && got[9] === 13, `got=${got.join()}`);

  pub.ws.close();
  await sleep(500);
  check('viewer receives publisher-gone when publisher closes', texts.includes('publisher-gone'), `texts=${JSON.stringify(texts)}`);

  viewer.ws.close();
  await sleep(500);
  check('mode kept after all sockets close -> /watch still canvas player', (await (await fetch(`${BASE}/watch/${bcode}`)).text()).includes("'/view/'"));
}

// ── Flow control: join replay, credit conservation, stall refill ─────────────
{
  const fcode = 'tc' + rnd(10);
  const fsecret = 'fc-' + rnd(8);
  await fetch(`${BASE}/token/${fcode}?role=publish&secret=${fsecret}`);
  const pubTexts = [];
  const pub = await openWs(`${WSB}/ingest/${fcode}?secret=${fsecret}`, { onmessage: e => { if (typeof e.data === 'string') pubTexts.push(e.data); } });
  await sleep(200);

  // Open a viewer that records frame ids and acks every `ackEvery`-th received
  // frame (0 = never), optionally `ackDelayMs` late to mimic a slow car link.
  // Current players connect with ?acks=recv; `legacy` mimics a page cached from
  // before that, which the relay rescues with one-frame stall refills.
  const viewerWith = async (ackEvery, ackDelayMs = 0, { legacy = false } = {}) => {
    const got = [];
    let n = 0, acks = 0, overshoot = 0;
    const v = await openWs(`${WSB}/view/${fcode}${legacy ? '' : '?acks=recv'}`, {
      binary: true,
      onmessage: e => {
        if (typeof e.data === 'string') return;
        got.push(new Uint8Array(e.data)[0]);
        n++;
        // The relay may only have sent what the window plus returned credit allows.
        overshoot = Math.max(overshoot, n - (8 + 4 * acks));
        if (ackEvery && n % ackEvery === 0) {
          const ws = e.target;
          if (ackDelayMs) setTimeout(() => { acks++; ws.send('ack'); }, ackDelayMs);
          else { acks++; ws.send('ack'); }
        }
      },
    });
    return { ws: v.ws, got, overshoot: () => overshoot };
  };
  const sendSpaced = async (from, count, gapMs) => {
    for (let i = 0; i < count; i++) { pub.ws.send(new Uint8Array([from + i])); await sleep(gapMs); }
  };
  const range = (from, count) => Array.from({ length: count }, (_, i) => from + i).join();

  // Pace the "every frame arrives" checks from the measured round trip, so they
  // also hold against a remote deployment: an ack sent after frame 4 must land
  // before the relay spends the other 4 credits.
  const probe = await openWs(`${WSB}/view/${fcode}`);
  let rtt = 0;
  for (let i = 0; i < 3; i++) {
    const t = Date.now();
    await new Promise(res => { probe.ws.onmessage = e => { if (e.data === 'pong') res(); }; probe.ws.send('ping'); });
    rtt = Math.max(rtt, Date.now() - t);
  }
  probe.ws.close();
  const gap = Math.max(10, Math.ceil(rtt / 3));

  pubTexts.length = 0;                     // the RTT probe above joined frameless too
  const a0 = await viewerWith(0);
  await sleep(300);
  check('viewer joining before any frame asks the publisher to resend', pubTexts.includes('need-frame') && a0.got.length === 0, `texts=${JSON.stringify(pubTexts)} got=${a0.got.join()}`);
  a0.ws.close();

  pub.ws.send(new Uint8Array([42]));
  await sleep(200);
  const a = await viewerWith(0);
  await sleep(300);
  check('joining viewer is replayed the latest frame immediately', a.got.join() === '42', `got=${a.got.join()}`);
  a.ws.close();

  const b = await viewerWith(4);           // the current player's cadence
  await sendSpaced(1, 30, gap);
  await sleep(300 + rtt);
  check('viewer acking every 4th received frame gets all 30', b.got.slice(1).join() === range(1, 30), `got=${b.got.join()} gap=${gap}`);
  b.ws.close();

  const slow = await viewerWith(4, 250);   // acks arrive 250 ms late: a slow car link
  await sendSpaced(1, 40, 10);
  await sleep(1200);
  check('slow viewer never has more frames in flight than it acked for', slow.overshoot() <= 0 && slow.got[slow.got.length - 1] === 40, `overshoot=${slow.overshoot()} got=${slow.got.join()}`);
  slow.ws.close();

  // Acks 2.5 s late — past the stall-refill delay — as on a car link carrying
  // well under 2 fps. A current player must still be held to its window.
  const crawl = await viewerWith(4, 2500);
  await sendSpaced(1, 50, 100);
  await sleep(3000);
  check('very slow current viewer gets no refills beyond its window', crawl.overshoot() <= 0, `overshoot=${crawl.overshoot()} got=${crawl.got.join()}`);
  crawl.ws.close();

  const quiet = await viewerWith(0);       // a current player that has gone silent
  await sleep(200);
  for (let i = 101; i <= 112; i++) pub.ws.send(new Uint8Array([i]));
  await sleep(2300);
  pub.ws.send(new Uint8Array([113]));
  await sleep(300);
  check('silent current viewer is held at its window (no refill)', quiet.got.slice(1).join() === range(101, 7), `got=${quiet.got.join()}`);
  quiet.ws.close();

  const c = await viewerWith(0, 0, { legacy: true });   // replay spends 1 of 8 credits
  await sleep(200);
  for (let i = 101; i <= 112; i++) pub.ws.send(new Uint8Array([i]));
  await sleep(300);
  check('never-acking legacy viewer stops at its window', c.got.slice(1).join() === range(101, 7), `got=${c.got.join()}`);
  await sleep(2000);                       // now past the 2 s stall refill
  pub.ws.send(new Uint8Array([113]));
  pub.ws.send(new Uint8Array([114]));
  await sleep(300);
  check('stall refill hands a stalled legacy page one fresh frame, not a window', c.got.slice(8).join() === '113', `got=${c.got.join()}`);
  c.ws.close();

  pub.ws.close();
  await sleep(300);
}

// ── Video upload + range serving ────────────────────────────────────────────
{
  const vcode = 'tc' + rnd(10);
  const vsecret = 'vid-' + rnd(8);
  await fetch(`${BASE}/token/${vcode}?role=publish&secret=${vsecret}`);

  const noAuth = await fetch(`${BASE}/upload-video/${vcode}`, { method: 'POST', body: 'x' });
  check('POST /upload-video w/o secret -> 403 (hardened)', noAuth.status === 403, `status=${noAuth.status}`);

  const empty = await fetch(`${BASE}/upload-video/${vcode}?secret=${vsecret}`, { method: 'POST', body: '' });
  check('POST /upload-video empty body -> 400', empty.status === 400, `status=${empty.status}`);

  const xss = await fetch(`${BASE}/upload-video/${vcode}?secret=${vsecret}`, {
    method: 'POST', body: '<script>alert(document.domain)</script>',
    headers: { 'Content-Type': 'text/html' },
  });
  check('upload with text/html accepted (stored)', xss.status === 200, `status=${xss.status}`);
  const served = await fetch(`${BASE}/video/${vcode}`);
  check('served Content-Type coerced to video/mp4 (no stored XSS)', served.headers.get('content-type') === 'video/mp4', `ct=${served.headers.get('content-type')}`);
  check('served with X-Content-Type-Options: nosniff', served.headers.get('x-content-type-options') === 'nosniff');

  const SIZE = 3.5 * 1024 * 1024;
  const payload = Buffer.alloc(SIZE);
  for (let i = 0; i < SIZE; i++) payload[i] = i % 251;
  const up = await fetch(`${BASE}/upload-video/${vcode}?secret=${vsecret}`, {
    method: 'POST', body: payload, headers: { 'Content-Type': 'video/mp4' },
  });
  check('upload 3.5MiB video -> 200 OK', up.status === 200, `status=${up.status}`);

  const head = await fetch(`${BASE}/video/${vcode}`, { method: 'HEAD' });
  check('HEAD /video -> 200 + Content-Length', head.status === 200 && head.headers.get('content-length') === String(SIZE), `cl=${head.headers.get('content-length')}`);
  check('HEAD /video Accept-Ranges bytes', head.headers.get('accept-ranges') === 'bytes');

  const full = await fetch(`${BASE}/video/${vcode}`);
  const fullBuf = Buffer.from(await full.arrayBuffer());
  check('GET /video full body byte-exact', full.status === 200 && fullBuf.length === SIZE && fullBuf.equals(payload), `len=${fullBuf.length}`);

  const start = 1048570, end = 1048580;
  const rr = await fetch(`${BASE}/video/${vcode}`, { headers: { Range: `bytes=${start}-${end}` } });
  const rb = Buffer.from(await rr.arrayBuffer());
  check('range across chunk boundary -> 206 correct bytes',
    rr.status === 206 && rb.equals(payload.subarray(start, end + 1)) &&
    rr.headers.get('content-range') === `bytes ${start}-${end}/${SIZE}`,
    `status=${rr.status} cr=${rr.headers.get('content-range')} len=${rb.length}`);

  const open = await fetch(`${BASE}/video/${vcode}`, { headers: { Range: 'bytes=0-' } });
  const ob = Buffer.from(await open.arrayBuffer());
  check('open-ended range bytes=0- -> whole file', open.status === 206 && ob.equals(payload), `len=${ob.length}`);

  const suffix = await fetch(`${BASE}/video/${vcode}`, { headers: { Range: 'bytes=-500' } });
  const sb = Buffer.from(await suffix.arrayBuffer());
  check('suffix range bytes=-500 -> LAST 500 bytes', suffix.status === 206 && sb.equals(payload.subarray(SIZE - 500)), `len=${sb.length} cr=${suffix.headers.get('content-range')}`);

  const unsat = await fetch(`${BASE}/video/${vcode}`, { headers: { Range: `bytes=${SIZE + 10}-` } });
  check('unsatisfiable range -> 416 + Content-Range bytes */total',
    unsat.status === 416 && unsat.headers.get('content-range') === `bytes */${SIZE}`,
    `status=${unsat.status} cr=${unsat.headers.get('content-range')}`);

  const noVideo = await fetch(`${BASE}/video/${'tc' + rnd(10)}`);
  check('GET /video with no upload -> 404 No video', noVideo.status === 404 && (await noVideo.text()) === 'No video');

  const small = Buffer.alloc(1000, 7);
  await fetch(`${BASE}/upload-video/${vcode}?secret=${vsecret}`, { method: 'POST', body: small, headers: { 'Content-Type': 'video/mp4' } });
  const after = await fetch(`${BASE}/video/${vcode}`);
  const ab = Buffer.from(await after.arrayBuffer());
  check('re-upload smaller video replaces old bytes', ab.length === 1000 && ab.equals(small), `len=${ab.length}`);

  const big = Buffer.alloc(65 * 1024 * 1024, 1);
  const tooBig = await fetch(`${BASE}/upload-video/${vcode}?secret=${vsecret}`, { method: 'POST', body: big, headers: { 'Content-Type': 'video/mp4' } });
  check('upload > 64MB -> 413', tooBig.status === 413, `status=${tooBig.status}`);
  const intact = await fetch(`${BASE}/video/${vcode}`);
  const ib = Buffer.from(await intact.arrayBuffer());
  check('previous video intact after rejected oversize upload', ib.equals(small), `len=${ib.length}`);
}

console.log(results.join('\n'));
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
