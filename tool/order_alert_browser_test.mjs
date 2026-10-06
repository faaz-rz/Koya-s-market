import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
const {chromium}=createRequire(import.meta.url)(process.env.KOYAS_PLAYWRIGHT_MODULE || 'playwright');
const output=path.resolve('outputs/order-alerts/browser');
await fs.mkdir(output,{recursive:true});
execFileSync('dart',['compile','js','-O2','-o',path.join(output,'probe.js'),'tool/order_alert_browser_probe.dart'],{stdio:'pipe'});
const html='<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Order alert test</title></head><body><button id="enable">Enable</button><button id="notify">New order</button><button id="clear">Clear</button><output id="result"></output><script defer src="probe.js"></script></body></html>';
await fs.writeFile(path.join(output,'index.html'),html);
(async()=>{
 const server=http.createServer(async(req,res)=>{try{const name=req.url==='/'?'index.html':req.url==='/probe.js'?'probe.js':null;if(!name){res.writeHead(404);res.end();return;}const file=path.join(output,name);const bytes=await fs.readFile(file);res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':'text/html');res.end(bytes);}catch{res.writeHead(404);res.end();}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const url=`http://127.0.0.1:${server.address().port}`;
 const browser=await chromium.launch({headless:true,args:['--mute-audio']});const report=[];
 try {
  for(const mode of ['granted','denied','unavailable','mobile-constructor-error']) {
   const context=await browser.newContext();const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(mode=>{
    window.__notifications=[];window.__oscillators=0;window.__opened=0;window.__permissionRequests=0;
    const audio=window.AudioContext.prototype.createOscillator;
    window.AudioContext.prototype.createOscillator=function(){window.__oscillators++;return audio.call(this);};
    if(mode==='unavailable'){delete window.Notification;return;}
    let permission=mode==='denied'?'denied':'default';
    window.Notification=class {
     static get permission(){return permission;}
     static requestPermission(){window.__permissionRequests++;permission='granted';return Promise.resolve(permission);}
     constructor(title,options){if(mode==='mobile-constructor-error')throw new TypeError('not supported');this.title=title;this.options=options;this.closed=false;window.__notifications.push(this);}
     close(){this.closed=true;}
    };
   },mode);
   await page.goto(url);await page.click('#enable');
   await page.waitForFunction(()=>document.querySelector('#result').textContent.includes('permission'));
   const enabled=JSON.parse(await page.locator('#result').textContent());assert.equal(enabled.sound,true);
   assert.equal(enabled.permission,mode==='denied'?'denied':mode==='unavailable'?'unavailable':'granted');
   await page.click('#notify');await page.waitForFunction(()=>document.querySelector('#result').textContent.includes('played'));
   const delivered=JSON.parse(await page.locator('#result').textContent());assert.equal(delivered.played,true);assert.equal(delivered.shown,mode==='granted');
   assert.equal(await page.evaluate(()=>window.__oscillators),2);assert.equal(await page.title(),'(1) Koya Stores Admin');
   if(mode==='granted'){
    const notification=await page.evaluate(()=>{const n=window.__notifications[0];return{title:n.title,body:n.options.body,tag:n.options.tag,silent:n.options.silent};});
    assert.equal(notification.body,'Open the order queue to review.');assert.equal(notification.silent,true);
    await page.evaluate(()=>window.__notifications[0].onclick(new Event('click')));assert.equal(await page.locator('#result').textContent(),'opened');
   }
   await page.click('#clear');assert.equal(await page.title(),'Koya Stores Admin');assert.deepEqual(errors,[]);
   report.push({mode,enabled,delivered,oscillator_count:2,uncaught_errors:0});await context.close();
  }
  await fs.writeFile(path.join(output,'../browser-verification.json'),JSON.stringify({headless:true,real_web_audio_context:true,notification_api_mocked:true,cases:report},null,2));console.log(JSON.stringify(report,null,2));
 } finally {await browser.close();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
