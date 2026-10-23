import {mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {chromium,browserOptions} from './test-browser.mjs';
const root=fileURLToPath(new URL('.',import.meta.url));
const base=process.env.REFERENCE_URL||'http://127.0.0.1:8767/library-first/app.html';
const scenes=['home','video-tags','video','packs','pack-tags','reader','settings','dark','vertical','readertags','readersettings','empty','pack-quick','roots','trash','backup','restore-preview','tasks'];
const browser=await chromium.launch(browserOptions);
try {
 const page=await browser.newPage({viewport:{width:390,height:844}});
 await mkdir(root+'shots',{recursive:true});
 for(const state of scenes){
  const url=new URL(base);url.searchParams.set('snapshot','1');if(state!=='home')url.searchParams.set('state',state);
  await page.goto(url.href);await page.locator('.app').waitFor({state:'visible'});
  await page.evaluate(()=>document.fonts.ready);
  await page.waitForTimeout(500);
  await page.screenshot({path:root+'shots/'+state+'.png'});
 }
 await page.setViewportSize({width:1440,height:1000});
 await page.goto(new URL('.',base).href);await page.evaluate(()=>document.fonts.ready);
 await page.screenshot({path:root+'shots/overview.png',fullPage:true});
 console.log(`Captured ${scenes.length} reference states and overview`);
} finally {await browser.close()}
