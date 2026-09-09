// Deterministic, local-only UI/SQLite smoke. No production reads or writes.
const {spawn} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const WebSocket = require('ws');
const wait = ms => new Promise(r => setTimeout(r, ms));
const output = path.resolve(__dirname, '../build/local-cache-check');
fs.mkdirSync(output, {recursive:true});
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'islander-cache-check-'));
const browser = spawn('/opt/google/chrome/chrome', ['--headless=new','--no-sandbox','--disable-gpu',
  '--enable-unsafe-swiftshader','--remote-debugging-port=9227',`--user-data-dir=${profile}`,'about:blank'], {stdio:'ignore'});
(async () => {
  let ws;
  let api;
  let server;
  try {
    const root=path.resolve(__dirname,'../build/local-cache-web');
    server=http.createServer((req,res)=>{
      let file;
      try {
        const pathname=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname);
        file=path.resolve(root,'.'+(pathname==='/'?'/index.html':pathname));
        if(!file.startsWith(root+path.sep))throw Error('invalid path');
      }catch{res.writeHead(400);res.end();return;}
      const types={'.html':'text/html','.txt':'text/plain; charset=utf-8','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.otf':'font/otf','.ttf':'font/ttf','.png':'image/png'};
      fs.readFile(file,(error,bytes)=>{if(error){res.writeHead(404);res.end();return;}
        res.setHeader('Content-Type',types[path.extname(file)]??'application/octet-stream');res.end(bytes);
      });
    });
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(8084,'127.0.0.1',resolve);});
    let tabs;
    for(let i=0;i<50;i++){try{tabs=await(await fetch('http://127.0.0.1:9227/json/list')).json();break;}catch{await wait(100);}}
    if(!tabs)throw Error('Chrome did not start');
    ws=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);
    await new Promise(r=>ws.once('open',r));
    const pending=new Map();let seq=0;const errors=[];
    const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{
      const id=++seq;const timer=setTimeout(()=>{pending.delete(id);reject(Error(method+' timed out'));},15000);
      pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));
    });
    const post={id:10,followId:0,plateId:1,title:'海风吹过的讨论',value:'沙滩上的本地缓存测试。加载后断网，也能找到这段话。',name:'测试岛民',time:1700000000,mediaUrl:'[]',lastReplyArr:[],replyArr:[],replyCount:0};
    ws.on('message',async raw=>{
      const event=JSON.parse(raw);
      if(event.id){const p=pending.get(event.id);if(!p)return;clearTimeout(p.timer);pending.delete(event.id);event.error?p.reject(Error(event.error.message)):p.resolve(event.result);}
      if(event.method==='Runtime.exceptionThrown')errors.push(JSON.stringify(event.params.exceptionDetails));
    });
    await send('Runtime.enable');await send('Page.enable');
    api=http.createServer((req,res)=>{
      res.setHeader('Access-Control-Allow-Origin','http://127.0.0.1:8084');
      res.setHeader('Access-Control-Allow-Methods','GET, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers','content-type, authorization');
      res.setHeader('Content-Type','application/json');
      if(!['GET','OPTIONS'].includes(req.method)){res.writeHead(405);res.end();return;}
      const uri=new URL(req.url,'http://127.0.0.1');
      const data=uri.pathname==='/plate/get'?[{id:1,name:'综合版',value:'日常讨论'}]:uri.pathname==='/forum/get'?post:{list:[post],count:1};
      res.end(JSON.stringify({code:200,data}));
    });
    await new Promise((resolve,reject)=>{api.once('error',reject);api.listen(8085,'127.0.0.1',resolve);});
    // Redirect only forum XHR requests to the local fixture. CDP Fetch interception
    // can suspend SharedWorker requests and invalidate a persistence test.
    await send('Page.addScriptToEvaluateOnNewDocument',{source:`
      const open=XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open=function(method,url,...rest){
        const u=new URL(url,location.href);
        if(['forum-api.islander.top','user-api.islander.top','api.nmb.best','bog.ac'].includes(u.hostname))
          url='http://127.0.0.1:8085'+u.pathname+u.search;
        return open.call(this,method,url,...rest);
      };
    `});
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-color-scheme',value:'light'}]});
    const evaluate=async expression=>(await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true})).result?.value;
    const semantics=async()=>{await evaluate("document.querySelector('flt-semantics-placeholder')?.click()");await wait(500);};
    const text=()=>evaluate("document.body.innerText+'\\n'+Array.from(document.querySelectorAll('[aria-label]')).map(e=>e.getAttribute('aria-label')).join('\\n')");
    const until=async (value)=>{for(let i=0;i<60;i++){await semantics();if((await text()).includes(value))return;await wait(250);}await shot('failure.png');throw Error('Missing UI: '+value+'; '+await text()+'; errors='+errors.join(';')+'; '+await evaluate('document.body.innerHTML.slice(0,500)'));};
    const shot=async name=>{const result=await send('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(output,name),Buffer.from(result.data,'base64'));};
    await send('Page.navigate',{url:'http://127.0.0.1:8084/#/plate/0'});
    await until('No.10');await wait(1800);
    // Merely loaded content must be visible without entering the thread or
    // supplying a query; this guards against the old browsed-only filter.
    await evaluate("location.hash='/local-search'");await until('海风吹过的讨论');
    await until('加载于');await until('多选');
    if((await text()).includes('选择已展示内容'))throw Error('Old bulk-select control remains');
    await evaluate("location.hash='/post/10'");await until('海风吹过的讨论');await wait(700);
    await evaluate("location.hash='/local-search'");await until('海风吹过的讨论');await shot('local-search-mobile.png');
    await until('浏览于');
    await send('Page.reload');await until('海风吹过的讨论');
    if(!(await text()).includes('浏览搜索'))throw Error('Reload did not reopen browse search');
    // A second document must not acquire the independent worker's database
    // lease. A static same-origin page makes no forum API requests.
    const second=await send('Target.createTarget',{url:'http://127.0.0.1:8084/assets/assets/fonts/OFL.txt'});
    try {
      const attached=await send('Target.attachToTarget',{targetId:second.targetId,flatten:true});
      await send('Runtime.enable',{},attached.sessionId);
      let locked=false;
      for(let i=0;i<20;i++) {
        const result=await send('Runtime.evaluate',{expression:"location.origin==='http://127.0.0.1:8084' && navigator.locks.request('islander-cache-v1',{ifAvailable:true},lock=>lock===null)",returnByValue:true,awaitPromise:true},attached.sessionId);
        if(result.result?.value===true){locked=true;break;}
        await wait(100);
      }
      if(!locked)throw Error('Second document could acquire the cache database lease');
    } finally {await send('Target.closeTarget',{targetId:second.targetId});await send('Page.bringToFront');}
    await evaluate("location.hash='/settings/cache'");await until('1 条 · 永久保留 0 条');await shot('cache-settings-mobile.png');
    await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-color-scheme',value:'dark'}]});await wait(700);await shot('cache-settings-dark.png');
    await send('Emulation.setDeviceMetricsOverride',{width:1280,height:900,deviceScaleFactor:1,mobile:false});
    await evaluate("location.hash='/local-search'");await until('海风吹过的讨论');await shot('local-search-desktop-dark.png');
    if(errors.length)throw Error(errors.join('\n'));
    console.log(JSON.stringify({ok:true,sqlitePersistence:'survives reload',crossTabLease:'exclusive',screenshots:output}));
  }finally{server?.close();api?.close();ws?.close();browser.kill('SIGTERM');}
})().catch(e=>{console.error(e);process.exitCode=1;});
