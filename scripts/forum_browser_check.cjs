// Read-only production smoke test. Requires local Chrome and the existing ws package.
const {spawn} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const WebSocket = require('ws');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const output = path.resolve(__dirname, '../../docs/岛民岛前端重构/flutter-prototype/screenshots');
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'islander-forum-check-'));
const browser = spawn(process.env.CHROME_EXECUTABLE || '/opt/google/chrome/chrome', [
  '--headless=new', '--no-sandbox', '--disable-gpu', '--enable-unsafe-swiftshader',
  '--remote-debugging-port=9223', `--user-data-dir=${profile}`, 'about:blank',
], {stdio: 'ignore'});

(async () => {
  let ws;
  try {
    let tabs;
    for (let i = 0; i < 40; i++) {
      try { tabs = await (await fetch('http://127.0.0.1:9223/json/list')).json(); break; }
      catch { await pause(250); }
    }
    if (!tabs) throw new Error('Chrome did not start');
    ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl);
    await new Promise(resolve => ws.once('open', resolve));
    let sequence = 0;
    const pending = new Map();
    const responses = new Map();
    const errors = [];
    const resourceFailures = [];
    const allowed = new Set(['/plate/get', '/forum/indexLast', '/forum/index', '/forum/get', '/forum/list', '/forum/postPage', '/forum/sage/list']);
    function send(method, params = {}) {
      return new Promise((resolve, reject) => {
        const id = ++sequence;
        const timeout = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 20000);
        pending.set(id, {resolve, reject, timeout}); ws.send(JSON.stringify({id, method, params}));
      });
    }
    ws.on('message', async raw => {
      const event = JSON.parse(raw);
      if (event.id) {
        const task = pending.get(event.id); if (!task) return;
        clearTimeout(task.timeout); pending.delete(event.id);
        if (event.error) task.reject(new Error(event.error.message)); else task.resolve(event.result);
      }
      if (event.method === 'Runtime.exceptionThrown') errors.push(event.params.exceptionDetails.text);
      if (event.method === 'Network.loadingFailed') resourceFailures.push(event.params.errorText);
      if (event.method === 'Network.responseReceived' && event.params.response.status === 200 && event.params.type !== 'Preflight' && event.params.response.url.includes('forum-api.islander.top')) {
        responses.set(event.params.requestId, event.params.response.url);
      }
      if (event.method === 'Fetch.requestPaused') {
        const request = event.params.request;
        const safe = ['GET', 'OPTIONS'].includes(request.method) && allowed.has(new URL(request.url).pathname);
        await send(safe ? 'Fetch.continueRequest' : 'Fetch.failRequest', {
          requestId: event.params.requestId, ...(safe ? {} : {errorReason: 'BlockedByClient'}),
        });
        if (!safe) errors.push(`Blocked unexpected API action: ${request.method} ${new URL(request.url).pathname}`);
      }
    });
    await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable');
    await send('Fetch.enable', {patterns: [{urlPattern: '*forum-api.islander.top/*'}, {urlPattern: '*user-api.islander.top/*'}]});
    await send('Emulation.setDeviceMetricsOverride', {width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false});
    await send('Page.navigate', {url: 'http://127.0.0.1:8083/#/plate/0'});
    await pause(25000);
    let firstId;
    for (const [requestId, url] of responses) {
      if (!url.includes('/forum/indexLast')) continue;
      const body = await send('Network.getResponseBody', {requestId});
      const data = JSON.parse(body.body);
      if (data.code !== 200 || !data.data.list?.length) throw new Error('Production timeline failed');
      firstId = data.data.list[0].id;
    }
    if (!firstId) {
      const shot = await send('Page.captureScreenshot', {format: 'png'});
      fs.writeFileSync('/tmp/islander-forum-browser-failure.png', Buffer.from(shot.data, 'base64'));
      const resources = await send('Runtime.evaluate', {expression: 'JSON.stringify(performance.getEntriesByType("resource").map(r=>r.name))'});
      throw new Error(JSON.stringify({message: 'No production timeline response observed', errors, resourceFailures, resources: resources.result?.value}));
    }
    fs.mkdirSync(output, {recursive: true});
    async function screenshot(name) {
      const result = await send('Page.captureScreenshot', {format: 'png'});
      fs.writeFileSync(path.join(output, name), Buffer.from(result.data, 'base64'));
    }
    await screenshot('forum-live-desktop.png');
    async function click(x, y) {
      await send('Input.dispatchMouseEvent', {type: 'mousePressed', x, y, button: 'left', clickCount: 1});
      await send('Input.dispatchMouseEvent', {type: 'mouseReleased', x, y, button: 'left', clickCount: 1});
      await pause(700);
    }
    if (process.argv.includes('--paging')) {
      await click(1260, 32); await screenshot('forum-page-jump-desktop.png');
      await click(700, 150);
    }
    if (process.argv.includes('--links')) {
      await send('Input.dispatchMouseEvent', {type: 'mouseWheel', x: 250, y: 620, deltaX: 0, deltaY: 680});
      await pause(700); await screenshot('forum-links-desktop.png');
    }
    await send('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 1, mobile: true});
    await pause(2000); await screenshot('forum-live-mobile.png');
    if (process.argv.includes('--paging')) {
      await click(350, 32); await screenshot('forum-page-jump-mobile.png');
      await click(200, 150);
    }
    if (process.argv.includes('--theme')) {
      await send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-color-scheme', value: 'dark'}]});
      await pause(1200); await screenshot('forum-dark-mobile.png');
      await click(350, 32); await screenshot('forum-dark-page-jump.png');
      await click(200, 150);
      await send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-color-scheme', value: 'light'}]});
      await pause(1200);
    }
    if (process.argv.includes('--previous')) {
      const pageReads = page => [...responses.values()].filter(raw => {
        const url = new URL(raw);
        return url.pathname === '/forum/indexLast' && url.searchParams.get('page') === String(page);
      }).length;
      await click(350, 32);
      await click(285, 756); // Next page in the page-jump sheet.
      await pause(1800);
      if (!pageReads(1)) throw new Error('Could not jump to the second page');
      const previousReads = pageReads(0);
      await send('Emulation.setTouchEmulationEnabled', {enabled: true});
      await send('Input.dispatchTouchEvent', {type: 'touchStart', touchPoints: [{x: 180, y: 260}]});
      for (const y of [300, 350, 400, 460, 530, 590]) {
        await send('Input.dispatchTouchEvent', {type: 'touchMove', touchPoints: [{x: 180, y}]});
        await pause(70);
      }
      await send('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []});
      await pause(2000);
      if (pageReads(0) <= previousReads) throw new Error('Pulling from the middle did not load the previous page');
      await screenshot('forum-previous-mobile.png');
    }
    if (process.argv.includes('--scroll')) {
      const appended = () => [...responses.values()].some(raw => {
        const url = new URL(raw);
        return url.pathname === '/forum/indexLast' && url.searchParams.get('page') === '1';
      });
      for (let i = 0; i < 45 && !appended(); i++) {
        await send('Input.dispatchMouseEvent', {type: 'mouseWheel', x: 200, y: 500, deltaX: 0, deltaY: 1000});
        await pause(400);
      }
      if (!appended()) throw new Error('Scrolling did not request the next production page');
      await pause(800); await screenshot('forum-infinite-mobile.png');
    }
    if (process.argv.includes('--links')) {
      await send('Input.dispatchMouseEvent', {type: 'mousePressed', x: 28, y: 32, button: 'left', clickCount: 1});
      await send('Input.dispatchMouseEvent', {type: 'mouseReleased', x: 28, y: 32, button: 'left', clickCount: 1});
      await pause(700);
      await send('Input.dispatchMouseEvent', {type: 'mouseWheel', x: 180, y: 500, deltaX: 0, deltaY: 700});
      await pause(700); await screenshot('forum-links-mobile.png');
    }
    await send('Page.navigate', {url: `http://127.0.0.1:8083/#/post/${firstId}`});
    await pause(7000); await screenshot('forum-live-thread.png');
    await send('Input.dispatchMouseEvent', {type: 'mousePressed', x: 330, y: 800, button: 'left', clickCount: 1});
    await send('Input.dispatchMouseEvent', {type: 'mouseReleased', x: 330, y: 800, button: 'left', clickCount: 1});
    await pause(1500); await screenshot('forum-live-cookie.png');
    if (errors.length) throw new Error(errors.join('\n'));
    console.log(JSON.stringify({passed: true, firstThreadId: firstId, apiResponses: responses.size, screenshots: output}));
  } finally { if (ws) ws.close(); browser.kill('SIGTERM'); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
