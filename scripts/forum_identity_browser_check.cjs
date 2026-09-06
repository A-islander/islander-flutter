// Isolated visual check: all islander.top API requests are fulfilled locally.
// Synthetic credentials never reach production. Requires Chrome and ws.
const {spawn} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const WebSocket = require('ws');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'islander-identity-check-'));
const output = path.resolve(__dirname, '../../docs/岛民岛前端重构/flutter-prototype/screenshots');
const browser = spawn('/opt/google/chrome/chrome', ['--headless=new', '--no-sandbox', '--disable-gpu',
  '--enable-unsafe-swiftshader', '--remote-debugging-port=9224', `--user-data-dir=${profile}`, 'about:blank'], {stdio: 'ignore'});
(async () => {
  let ws;
  try {
    let tabs;
    for (let i = 0; i < 40; i++) {
      try { tabs = await (await fetch('http://127.0.0.1:9224/json/list')).json(); break; }
      catch { await pause(250); }
    }
    if (!tabs) throw Error('Chrome did not start');
    ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl);
    await new Promise(resolve => ws.once('open', resolve));
    let sequence = 0;
    const pending = new Map(), errors = [];
    function send(method, params = {}) {
      return new Promise((resolve, reject) => {
        const id = ++sequence;
        const timer = setTimeout(() => { pending.delete(id); reject(Error(`Timed out: ${method}`)); }, 20000);
        pending.set(id, {resolve, reject, timer}); ws.send(JSON.stringify({id, method, params}));
      });
    }
    ws.on('message', async raw => {
      const event = JSON.parse(raw);
      if (event.id) {
        const task = pending.get(event.id); if (!task) return;
        clearTimeout(task.timer); pending.delete(event.id);
        event.error ? task.reject(Error(event.error.message)) : task.resolve(event.result);
      }
      if (event.method === 'Runtime.exceptionThrown') errors.push(event.params.exceptionDetails.text);
      if (event.method === 'Fetch.requestPaused') {
        const request = event.params.request;
        const url = new URL(request.url);
        const post = {id: 10, plateId: 1, userId: 8, name: '海边岛民', title: '沙滩边的日常',
          value: '今天也来岛上坐一会儿。', time: 1788624000, status: 0, replyCount: 1,
          followId: 0, mediaUrl: '[]', replyArr: [], lastReplyArr: []};
        const data = url.pathname === '/plate/get'
          ? [{id: 1, name: '综合版', status: 0, value: '岛民的日常'}, {id: 2, name: '技术版', status: 0, value: '开发交流'}]
          : url.pathname === '/user/get' ? {id: 7, name: '海盐汽水'}
          : url.pathname === '/forum/get' ? post : {list: [post], count: 1};
        if (!['GET', 'OPTIONS'].includes(request.method)) errors.push('Unexpected mutation attempted');
        await send('Fetch.fulfillRequest', {requestId: event.params.requestId, responseCode: 200,
          responseHeaders: [{name: 'Content-Type', value: 'application/json'},
            {name: 'Access-Control-Allow-Origin', value: '*'},
            {name: 'Access-Control-Allow-Headers', value: '*'},
            {name: 'Access-Control-Allow-Methods', value: 'GET,OPTIONS'}],
          body: Buffer.from(JSON.stringify({code: 200, data, msg: 'ok'})).toString('base64')});
      }
    });
    await send('Page.enable'); await send('Runtime.enable');
    await send('Fetch.enable', {patterns: [{urlPattern: '*islander.top/*'}]});
    await send('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 1, mobile: false});
    await send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-color-scheme', value: 'light'}]});
    await send('Page.addScriptToEvaluateOnNewDocument', {source: `
      if (location.host === '127.0.0.1:8083' && !localStorage.getItem('flutter.islander.cookie-vault.v1')) {
        const a = 'a'.repeat(32), b = 'b'.repeat(32);
        localStorage.setItem('flutter.islander.cookie-vault.v1', JSON.stringify(JSON.stringify({
          version: 1, activeId: a, cookies: [
            {id: a, token: 'visual-fixture-a', name: '海盐汽水', userId: 7, label: '日常饼干', invalid: false},
            {id: b, token: 'visual-fixture-b', name: '月亮湾', userId: 8, label: '备用饼干', invalid: false}]})));
        localStorage.setItem('flutter.islander.draft.v1.' + a + '.board.1', JSON.stringify(JSON.stringify({
          version: 1, title: '留给明天的一点想法', body: 'No.10 今天在海边散步，想把这段故事慢慢写完。\\n( ´▽｀)',
          boardId: 1, threadId: null, media: []})));
      }
    `});
    async function click(x, y) {
      await send('Input.dispatchMouseEvent', {type: 'mousePressed', x, y, button: 'left', clickCount: 1});
      await send('Input.dispatchMouseEvent', {type: 'mouseReleased', x, y, button: 'left', clickCount: 1});
      await pause(2500);
    }
    async function screenshot(name) {
      fs.mkdirSync(output, {recursive: true});
      const shot = await send('Page.captureScreenshot', {format: 'png'});
      fs.writeFileSync(path.join(output, name), Buffer.from(shot.data, 'base64'));
    }
    await send('Page.navigate', {url: 'http://127.0.0.1:8083/#/plate/0'});
    await pause(20000);
    if (process.argv.includes('--pagination')) {
      await screenshot('forum-pagination-mobile.png');
      await send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-color-scheme', value: 'dark'}]});
      await pause(1000); await screenshot('forum-pagination-dark-mobile.png');
      await send('Emulation.setDeviceMetricsOverride', {width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false});
      await send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-color-scheme', value: 'light'}]});
      await pause(1000); await screenshot('forum-pagination-desktop.png');
      if (errors.length) throw Error(errors.join('\n'));
      console.log(JSON.stringify({passed: true, mode: 'local mocked pagination UI', screenshots: output}));
      return;
    }
    await click(298, 32); await screenshot('forum-cookies-mobile.png');
    await send('Page.reload', {ignoreCache: true});
    await pause(6000);
    await click(340, 800); await screenshot('forum-draft-mobile.png');
    await send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-color-scheme', value: 'dark'}]});
    await pause(1000); await screenshot('forum-draft-dark-mobile.png');
    if (errors.length) throw Error(errors.join('\n'));
    console.log(JSON.stringify({passed: true, mode: 'local mocked API only', screenshots: output}));
  } finally { if (ws) ws.close(); browser.kill('SIGTERM'); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
