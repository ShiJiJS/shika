// Browser-level checks against the disposable HTML prototype, never the NAS.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.VIDEO_VIEWER_PLAYWRIGHT || 'C:/Users/Todoki/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=path.dirname(fileURLToPath(import.meta.url));
const base=process.env.VIDEO_VIEWER_PREVIEW || 'http://127.0.0.1:8766/p2/';
const browser=await chromium.launch({headless:true,executablePath:process.env.VIDEO_VIEWER_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
const reports=[];
const btn=(page,name)=>page.getByRole('button',{name,exact:true});
const sheet=page=>page.locator('.sheet');
const nav=async(page,name)=>page.locator('nav').getByRole('button',{name,exact:true}).click();
const ready=async page=>{await page.locator('.topbar h1').waitFor();await page.waitForFunction(()=>document.querySelector('#player').getAttribute('src')!==null || document.querySelector('.library-grid .video-tile')!==null || document.querySelector('.page-body.settings').checkVisibility());};
async function check(name,fn){
  const context=await browser.newContext({viewport:{width:390,height:844},acceptDownloads:true});
  const page=await context.newPage();page.setDefaultTimeout(12000);const errors=[];page.on('pageerror',e=>errors.push(e.message));
  try{await page.goto(base);await ready(page);await fn(page,context);assert.deepEqual(errors,[]);reports.push({name,passed:true});console.log('PASS '+name);}
  catch(e){await page.screenshot({path:path.join(root,'validation-failure.png')});reports.push({name,passed:false,error:e.message});console.log('FAIL '+name+': '+e.message);}
  finally{await context.close();}
}

try{
await check('folder hierarchy, intersection filtering, order and refresh persistence',async page=>{
  await btn(page,'选择文件夹').click();
  for(const p of ['/videos','/videos/收集','/videos/收集/花草','/videos/收集/花草/竖版'])await page.locator(`.folder-row[data-path="${p}"]`).click();
  await btn(page,'使用此目录').click();await page.waitForFunction(()=>document.querySelector('.position').textContent.replace(/\s/g,'').endsWith('/02'));
  await nav(page,'标签');await page.getByRole('button',{name:'花卉',exact:true}).click();await nav(page,'浏览');await page.waitForFunction(()=>document.querySelector('.position').textContent.replace(/\s/g,'').endsWith('/01'));
  assert.equal(await page.locator('.tag-filter[data-tag="花卉"]').getAttribute('aria-pressed'),'true');
  await btn(page,'播放模式：随机').click();await sheet(page).getByRole('button',{name:/顺序播放/}).click();
  await page.reload();await ready(page);assert.equal(await btn(page,'播放模式：顺序').count(),1);assert.equal(await page.locator('.tag-filter[data-tag="花卉"]').getAttribute('aria-pressed'),'true');
  await btn(page,'选择文件夹').click();assert.match(await page.locator('.scope-current').textContent(),/竖版/);
  await sheet(page).getByRole('button',{name:'媒体目录',exact:true}).click();await btn(page,'使用全部目录').click();
  await page.locator('.tag-filter[data-tag="花卉"]').click();await page.waitForFunction(()=>document.querySelector('.position').textContent.replace(/\s/g,'').endsWith('/06'));
});

await check('actual playback, no-repeat round, backtracking, resume and fullscreen',async page=>{
  await btn(page,'播放模式：随机').click();await sheet(page).getByRole('button',{name:/顺序播放/}).click();
  const seen=[];
  for(let i=0;i<6;i++){await page.waitForFunction(()=>!!document.querySelector('#player').getAttribute('aria-label'));seen.push(await page.locator('#player').getAttribute('aria-label'));if(i<5){await page.keyboard.press('ArrowDown');await page.waitForFunction(n=>document.querySelector('.position').textContent.trim().startsWith(String(n).padStart(2,'0')),i+2);}}
  assert.equal(new Set(seen).size,6);
  await page.keyboard.press('ArrowDown');await page.locator('.end-note').waitFor({state:'visible'});
  await page.keyboard.press('ArrowUp');const previous=await page.locator('#player').getAttribute('aria-label');assert.equal(previous,seen[4]);
  await page.reload();await ready(page);assert.equal(await page.locator('#player').getAttribute('aria-label'),previous);
  if(await page.locator('.surface').getAttribute('aria-label')==='播放视频')await page.locator('.surface').click();
  await page.waitForFunction(()=>!document.querySelector('#player').paused&&document.querySelector('#player').currentTime>0.15);
  await page.locator('.surface').click();await page.waitForFunction(()=>document.querySelector('#player').paused);
  await page.goto(base+'?state=landscape');await ready(page);await btn(page,'横屏全屏播放').click();await page.waitForFunction(()=>document.querySelector('.viewer').classList.contains('is-wide'));
  await btn(page,'退出横屏全屏').click();await page.waitForFunction(()=>!document.querySelector('.viewer').classList.contains('is-wide'));
});

await check('tag CRUD, batch append, search and read after refresh',async page=>{
  await nav(page,'标签');await btn(page,'新建标签').click();await page.getByLabel('标签名称',{exact:true}).fill('植物');await sheet(page).getByRole('button',{name:'保存',exact:true}).click();
  await nav(page,'视频库');await btn(page,'多选').click();await page.locator('.tile-select').nth(0).click();await page.locator('.tile-select').nth(1).click();await page.locator('.batchbar:visible').getByRole('button',{name:'打标签',exact:true}).click();await sheet(page).getByRole('button',{name:'植物',exact:true}).click();await btn(page,'完成').click();
  await page.reload();await ready(page);await nav(page,'标签');const row=page.locator('.row').filter({has:page.getByRole('button',{name:'植物',exact:true})});assert.equal((await row.locator('.tag-count').textContent()).trim(),'2');
  await btn(page,'重命名 植物').click();await page.getByLabel('标签名称',{exact:true}).fill('花园');await sheet(page).getByRole('button',{name:'保存',exact:true}).click();await page.getByRole('button',{name:'花园',exact:true}).click();assert.equal(await page.locator('.video-tile:visible').count(),2);
  await nav(page,'标签');await btn(page,'删除标签 花园').click();await sheet(page).getByRole('button',{name:'删除标签',exact:true}).click();await nav(page,'视频库');await page.waitForFunction(()=>[...document.querySelectorAll('.video-tile')].filter(e=>e.checkVisibility()).length===6);
});

await check('delete next, exact undo, recycle restore and permanent-delete confirmation',async page=>{
  const name=await page.locator('#player').getAttribute('aria-label');await btn(page,'更多').click();await page.getByRole('menuitem',{name:'移入回收站',exact:true}).click();await page.getByText('已移入回收站',{exact:true}).waitFor();assert.notEqual(await page.locator('#player').getAttribute('aria-label'),name);
  await btn(page,'撤销').click();await page.waitForFunction(name=>document.querySelector('#player').getAttribute('aria-label')===name,name);
  await nav(page,'设置');await page.getByRole('button',{name:/回收站.*1 个视频/}).click();await page.locator('.trash-check').check();await page.locator('.batchbar:visible').getByRole('button',{name:'恢复',exact:true}).click();await page.getByText('回收站是空的',{exact:true}).waitFor();
  await nav(page,'浏览');await btn(page,'更多').click();await page.getByRole('menuitem',{name:'移入回收站',exact:true}).click();await page.getByText('已移入回收站',{exact:true}).waitFor();await nav(page,'设置');await page.getByRole('button',{name:/回收站.*1 个视频/}).click();await page.locator('.trash-check').check();await btn(page,'永久删除').click();await btn(page,'取消').click();assert.equal(await page.locator('.trash-check:visible').count(),1);
  await btn(page,'永久删除').click();await sheet(page).getByRole('button',{name:'永久删除',exact:true}).click();await page.getByText('回收站是空的',{exact:true}).waitFor();await page.reload();await ready(page);await nav(page,'设置');await page.getByRole('button',{name:/回收站.*0 个视频/}).click();await page.getByText('回收站是空的',{exact:true}).waitFor();
});


await check('quick review filters, tag edit, delete/undo and daily-view return preserve paths',async page=>{
  await nav(page,'视频库');await btn(page,'快速整理').click();await page.getByRole('heading',{name:'快速整理',exact:true}).waitFor();
  await btn(page,'筛选整理范围').click();await sheet(page).getByRole('button',{name:'自然',exact:true}).click();await page.getByLabel('整理画面方向',{exact:true}).selectOption('portrait');await btn(page,'应用筛选').click();await page.waitForFunction(()=>document.querySelector('.position').textContent.replace(/\s/g,'').endsWith('/02'));
  const first=await page.locator('#player').getAttribute('aria-label');await btn(page,'更多').click();await page.getByRole('menuitem',{name:'视频详情',exact:true}).click();const before=await sheet(page).locator('.path').textContent();await btn(page,'关闭面板').click();
  await page.locator('.review-dock').getByRole('button',{name:'打标签',exact:true}).click();await sheet(page).getByRole('button',{name:'庭院',exact:true}).click();await btn(page,'完成').click();assert.equal(await page.locator('.tag-filter[data-tag="庭院"]').count(),1);
  await btn(page,'删除当前视频').click();await page.getByText('已移入回收站',{exact:true}).waitFor();assert.notEqual(await page.locator('#player').getAttribute('aria-label'),first);await btn(page,'撤销').click();await page.waitForFunction(name=>document.querySelector('#player').getAttribute('aria-label')===name,first);
  await btn(page,'更多').click();await page.getByRole('menuitem',{name:'视频详情',exact:true}).click();assert.equal(await sheet(page).locator('.path').textContent(),before);await btn(page,'关闭面板').click();
  await btn(page,'更多').click();await page.getByRole('menuitem',{name:'返回日常浏览',exact:true}).click();await page.getByRole('heading',{name:'浏览',exact:true}).waitFor();assert.equal(await page.locator('.review-dock').isVisible(),false);
  await nav(page,'视频库');await btn(page,'快速整理').click();await btn(page,'筛选整理范围').click();await page.getByLabel('整理时长',{exact:true}).selectOption('long');await btn(page,'应用筛选').click();await page.getByText('没有符合条件的可播放视频',{exact:true}).waitFor();await btn(page,'更多').click();await page.getByRole('menuitem',{name:'返回日常浏览',exact:true}).click();await page.getByRole('heading',{name:'浏览',exact:true}).waitFor();
  await nav(page,'设置');assert.equal(await page.getByRole('button',{name:/归档分类/}).count(),0);
});

await check('backup downloads, invalid imports stay safe, confirmed restore reads back',async page=>{
  await nav(page,'设置');await page.getByRole('button',{name:/备份与恢复/}).click();const [download]=await Promise.all([page.waitForEvent('download'),btn(page,'导出备份').click()]);const file=path.join(root,'validation-backup.json');await download.saveAs(file);const data=JSON.parse(await fs.readFile(file,'utf8'));assert.equal(data.format,'video-viewer-management');assert.equal(data.data.connection,undefined);assert.equal(data.data.categories,undefined);assert.equal(JSON.stringify(data).includes('passphrase'),false);
  await page.locator('#backup-file').setInputFiles({name:'bad.json',mimeType:'application/json',buffer:Buffer.from('{broken')});await page.getByRole('alert').getByText('备份文件不是有效的 JSON',{exact:true}).waitFor();await btn(page,'关闭错误提示').click();
  await nav(page,'标签');await btn(page,'新建标签').click();await page.getByLabel('标签名称',{exact:true}).fill('恢复前新增');await sheet(page).getByRole('button',{name:'保存',exact:true}).click();await nav(page,'设置');await page.getByRole('button',{name:/备份与恢复/}).click();await page.locator('#backup-file').setInputFiles(file);await btn(page,'恢复管理数据').click();await page.getByText('请确认替换现有管理数据',{exact:true}).waitFor();await page.getByLabel('确认替换现有管理数据',{exact:true}).check();await btn(page,'恢复管理数据').click();await page.getByText('管理数据已恢复',{exact:true}).waitFor();await nav(page,'标签');assert.equal(await page.getByRole('button',{name:'恢复前新增',exact:true}).count(),0);await page.reload();await ready(page);await nav(page,'标签');assert.equal(await page.getByRole('button',{name:'恢复前新增',exact:true}).count(),0);await fs.unlink(file);
});

await check('operation failure does not advance or claim success',async page=>{
  await page.goto(base+'?scenario=write-failure');await ready(page);const before=await page.locator('#player').getAttribute('aria-label');await btn(page,'更多').click();await page.getByRole('menuitem',{name:'移入回收站',exact:true}).click();await page.getByRole('alert').getByText(/目录没有写入权限/).waitFor();assert.equal(await page.locator('#player').getAttribute('aria-label'),before);assert.equal(await btn(page,'撤销').isVisible(),false);
  await page.goto(base+'?scenario=storage-failure');await ready(page);await nav(page,'标签');await btn(page,'新建标签').click();await page.getByLabel('标签名称',{exact:true}).fill('不应保存');await sheet(page).getByRole('button',{name:'保存',exact:true}).click();await page.getByRole('alert').getByText(/保存失败/).waitFor();await btn(page,'关闭面板').click();assert.equal(await page.getByRole('button',{name:'不应保存',exact:true}).count(),0);
});

await check('connection error, unavailable root and empty result recovery',async page=>{
  await nav(page,'设置');await page.getByRole('button',{name:/服务连接/}).click();await page.getByLabel('个人口令',{exact:true}).fill('wrong');await btn(page,'连接').click();await page.getByRole('alert').getByText(/口令不正确/).waitFor();await page.getByLabel('个人口令',{exact:true}).fill('demo');await btn(page,'连接').click();await page.locator('.viewer:visible').waitFor();
  await page.goto(base+'?page=roots&scenario=root-unavailable');await ready(page);assert.equal(await page.getByText('目录暂不可用',{exact:true}).count(),1);assert.equal(await page.getByText('去年花开_07.mp4',{exact:true}).count(),1);await btn(page,'刷新媒体目录').click();await page.getByRole('alert').getByText(/保留已有视频及标签记录/).waitFor();
  await page.goto(base);await ready(page);await nav(page,'视频库');await btn(page,'属性筛选').click();await page.getByLabel('时长',{exact:true}).selectOption('long');await btn(page,'应用').click();await page.getByText('没有符合条件的视频',{exact:true}).waitFor();await btn(page,'清除条件').click();assert.equal(await page.locator('.video-tile:visible').count(),6);
});
}finally{await browser.close();await fs.writeFile(path.join(root,'validation-report.json'),JSON.stringify({testedAt:new Date().toISOString(),checks:reports},null,2));}
if(reports.some(r=>!r.passed))process.exitCode=1;
