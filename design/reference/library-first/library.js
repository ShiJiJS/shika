const LIBRARY_STORE='liubai-library-first-v3';
const newScope=()=>({search:'',tags:[],folder:'',orientation:'all',duration:'all',status:'全部',sort:'名称'});
window.libraryApp=()=>Object.defineProperties(productApp(),Object.getOwnPropertyDescriptors({
 tab:'library',kind:'video',screen:'home',panel:'',fromTags:false,
 scopes:{video:newScope(),pack:newScope()},tagSelections:{video:[],pack:[]},
 tagCatalog:{video:['户外','自然','喜欢'],pack:['和服','户外','白裙','角色','喜欢']},
 tagKind:'pack',editingTagKind:'video',createName:'',manageMode:'rename',pendingImport:null,
 queueIds:[],queueOriginal:[],queueAt:0,queueLabel:'',queueOrigin:null,queueOrder:'顺序',videoGesture:null,
 trashKind:'video',lastRemoved:null,libraryScrolls:{video:0,pack:0},returnContext:null,packQuick:false,menuPackId:'',
 get menuPack(){return this.packs.find(p=>p.id===this.menuPackId)},
 openPackActions(id){this.chosen=[];this.menuPackId=id;this.panel='packActions'},
 startPackQuick(id){const target=id||this.filteredItems[0]?.id;if(!target)return;this.openPack(target);this.packQuick=true;this.controls=true;this.panel=''},
 removePackNow(){if(!this.packQuick)return;this.deleteId=this.pack.id;this.trash()},
 get navItems(){return [['library','媒体库','grid'],['tags','标签','tag'],['recent','最近','history'],['settings','设置','settings']]},
 get title(){return this.fromTags&&this.tab==='library'?'标签结果':({library:'媒体库',tags:'标签',recent:'最近看过',settings:'设置'})[this.tab]},
 get activeNav(){return this.fromTags&&this.tab==='library'?'tags':this.tab},
 get typeName(){return this.kind==='video'?'视频':'图包'},
 get itemUnit(){return this.kind==='video'?'个视频':'个图包'},
 get scope(){return this.scopes[this.kind]},
 get search(){return this.scope.search},set search(v){this.scope.search=v},
 get filters(){return this.scope.tags},set filters(v){this.scope.tags=v},
 get statusFilter(){return this.scope.status},set statusFilter(v){this.scope.status=v},
 get sort(){return this.scope.sort},set sort(v){this.scope.sort=v},
 get tagSelection(){return this.tagSelections[this.kind]},set tagSelection(v){this.tagSelections[this.kind]=v},
 get currentCatalog(){return this.tagCatalog[this.kind]},
 get allTags(){return this.tagCatalog[this.tagKind]},
 get itemsOfKind(){return this.available.filter(i=>i.type===this.kind)},
 get filteredItems(){const s=this.scope;return this.itemsOfKind.filter(i=>s.tags.every(t=>i.tags.includes(t))&&(!s.search||`${i.title} ${i.author} ${i.folder}`.toLowerCase().includes(s.search.toLowerCase()))&&(!s.folder||i.folder.startsWith(s.folder))&&(this.kind!=='video'||((s.orientation==='all'||i.id.includes(s.orientation))&&(s.duration==='all'||(s.duration==='short'))))&&(s.status!=='未读'||this.progress[i.id]===undefined)&&(s.status!=='在读'||(this.progress[i.id]!==undefined&&this.progress[i.id]<i.pages.length-1))&&(s.status!=='已读'||this.progress[i.id]>=i.pages.length-1)).sort((a,b)=>s.sort==='名称'?a.title.localeCompare(b.title,'zh-CN'):this.allItems.indexOf(b)-this.allItems.indexOf(a))},
 get tagResults(){return this.itemsOfKind.filter(i=>this.tagSelection.every(t=>i.tags.includes(t)))},
 get recentItems(){return this.history.map(id=>this.available.find(i=>i.id===id&&i.type===this.kind)).filter(Boolean)},
 get continuePack(){return this.recentItems.find(i=>i.type==='pack'&&this.filteredItems.some(x=>x.id===i.id))},
 get hasScope(){return !!(this.search||this.filters.length||this.scope.folder||this.scope.orientation!=='all'||this.scope.duration!=='all'||this.statusFilter!=='全部')},
 get scopeLabel(){return [this.scope.folder&&'目录：'+this.scope.folder+'（含子目录）',...this.filters.map(t=>'# '+t),this.search&&'搜索：'+this.search,this.scope.orientation!=='all'&&(this.scope.orientation==='portrait'?'方向：竖屏':'方向：横屏'),this.scope.duration!=='all'&&(this.scope.duration==='short'?'15 秒以内':'15 秒以上'),this.statusFilter!=='全部'&&this.statusFilter].filter(Boolean).join(' · ')||'全部'+this.typeName},
 get nextPack(){return this.packs.find(p=>p.id===this.queueIds[this.queueAt+1])||null},
 get tagTargets(){const pool=this.tagKind==='video'?this.videos:this.packs;return pool.filter(i=>(this.chosen.length?this.chosen:[this.targetId]).includes(i.id))},
 get trashItems(){return this.allItems.filter(i=>i.type===this.trashKind&&this.trashIds.includes(i.id))},
 get sheetTitle(){return ({tags:(this.tagKind==='video'?'视频标签':'图包标签')+(this.chosen.length?' · 批量追加':''),'reader-settings':'阅读设置',overview:'页码总览',filter:this.typeName+'筛选',folder:this.typeName+'目录',queue:'本次预览范围',packActions:'图包操作',packScope:'本次图包范围','pack-more':'图包操作',finished:'读完本包',details:'图包详情',connection:'服务器连接',roots:'媒体目录',defaults:'阅读偏好',trash:'回收站',backup:'备份与恢复',rename:'管理'+(this.editingTagKind==='video'?'视频':'图包')+'标签',create:'新建'+this.typeName+'标签',delete:'移入回收站',removeTag:'移除标签',restoreBackup:'恢复备份',videoMore:'视频操作','queue-end':'已到本次范围末尾'})[this.panel]||'设置'},
 init(){
  this.videos.forEach(v=>v.folder=v.id==='v-portrait'?'短视频 / 竖屏':'短视频 / 横屏');
  try{const d=qs.has('snapshot')?null:JSON.parse(localStorage.getItem(LIBRARY_STORE)||'null');if(d){for(const k of ['progress','preferences','last','history','trashIds','defaultMode','rootEnabled','tagCatalog','connection'])if(d[k]!==undefined)this[k]=d[k];[...this.packs,...this.videos].forEach(i=>{if(d.tags?.[i.id])i.tags=d.tags[i.id]})}}catch{this.error='本地记录无法读取，仍可浏览内容。'}
  const s=qs.get('state');if(['packs','pack-tags','reader','vertical','readertags','readersettings','pack-quick'].includes(s))this.kind='pack';
  if(['video-tags','pack-tags'].includes(s)){this.tab='tags';this.tagSelection=[this.kind==='video'?'户外':'和服']}
  if(s==='results'){this.kind='video';this.tab='tags';this.tagSelection=['户外'];this.showTagResults()}
  if(s==='video'){this.filters=['户外'];this.startVideo(this.filteredItems[0]?.id)}
  if(['reader','vertical','readertags','readersettings'].includes(s)){this.openPack('summer');if(s==='vertical')this.changeMode('vertical');if(s==='readertags')this.editTags('summer');if(s==='readersettings')this.panel='reader-settings'}
  if(s==='pack-quick')this.startPackQuick('summer');
  if(['settings','recent'].includes(s))this.tab=s;
  if(s==='empty'){this.filters=['自然','喜欢']}
  this.$watch('panel',p=>{if(p)this.$nextTick(()=>this.$refs.sheet?.focus())});
 },
 toast(s){this.notice=s;clearTimeout(this._toast);this._toast=setTimeout(()=>{this.notice='';this.lastRemoved=null},8000)},
 snapshotData(){return {progress:this.progress,preferences:this.preferences,last:this.last,history:this.history,trashIds:this.trashIds,defaultMode:this.defaultMode,rootEnabled:this.rootEnabled,tagCatalog:this.tagCatalog,connection:this.connection,tags:Object.fromEntries([...this.packs,...this.videos].map(i=>[i.id,i.tags]))}},
 save(){try{if(qs.has('snapshot'))return true;if(qs.get('scenario')==='storage-failure')throw Error();localStorage.setItem(LIBRARY_STORE,JSON.stringify(this.snapshotData()));return true}catch{this.error='保存失败，修改尚未写入。当前输入已保留，请重试。';return false}},
 nav(n){this.packQuick=false;this.pauseVideo();this.rememberScroll();this.tab=n;this.screen='home';this.panel='';this.fromTags=false;this.multi=false;this.chosen=[];this.restoreScroll()},
 rememberScroll(){if(this.tab==='library'&&this.$refs.library)this.libraryScrolls[this.kind]=this.$refs.library.scrollTop},
 restoreScroll(){this.$nextTick(()=>{if(this.$refs.library)this.$refs.library.scrollTop=this.libraryScrolls[this.kind]||0})},
 setKind(k){this.rememberScroll();this.kind=k;this.fromTags=false;this.multi=false;this.chosen=[];this.restoreScroll()},
 clearScope(){this.scopes[this.kind]=newScope();this.chosen=[]},
 setFilter(t){this.filters=this.filters.includes(t)?this.filters.filter(x=>x!==t):[...this.filters,t];this.chosen=[]},
 toggleTagSelection(t){this.tagSelection=this.tagSelection.includes(t)?this.tagSelection.filter(x=>x!==t):[...this.tagSelection,t]},
 showTagResults(){this.scopes[this.kind]={...newScope(),tags:[...this.tagSelection]};this.tab='library';this.fromTags=true;this.multi=false;this.chosen=[];this.libraryScrolls[this.kind]=0;this.restoreScroll()},
 previewTags(){this.beginQueue(this.tagResults,'标签 · '+(this.tagSelection.map(t=>'# '+t).join(' + ')||'全部视频'),this.tagResults[0]?.id)},
 sourceContext(){return {tab:this.tab,kind:this.kind,fromTags:this.fromTags,scroll:this.$refs.library?.scrollTop||0}},
 beginQueue(items,label,id){if(!items.length||!id)return;this.returnContext=this.sourceContext();this.queueOrigin=JSON.parse(JSON.stringify(this.returnContext));this.queueIds=items.map(i=>i.id);this.queueOriginal=[...this.queueIds];this.queueAt=this.queueIds.indexOf(id);this.queueLabel=label;this.queueOrder='顺序';this.quick=false;this.chosen=[];this.activateVideo(id)},
 startVideo(id){const items=this.tab==='recent'?this.recentItems:this.filteredItems;this.beginQueue(items,this.tab==='recent'?'最近 · 最近看过的视频':(this.fromTags?'标签结果':'媒体库')+' · '+this.scopeLabel,id||items[0]?.id)},
 activateVideo(id){this.pauseVideo();this.videoIndex=this.videos.findIndex(v=>v.id===id);if(this.videoIndex<0)return;this.screen='video';this.panel='';this.videoTime=0;this.videoDuration=0;this.videoError=false;this.videoControls=true;this.touchHistory(id);this.$nextTick(()=>document.querySelector('video')?.load())},
 openItem(i){if(this.multi){this.selectPack(i.id);return}i.type==='video'?this.startVideo(i.id):this.openPack(i.id)},
 closeContent(){this.pauseVideo();const c=this.returnContext||{tab:'library',kind:this.kind,fromTags:false,scroll:0};this.screen='home';this.panel='';this.quick=false;this.packQuick=false;this.tab=c.tab;this.kind=c.kind;this.fromTags=c.fromTags;this.$nextTick(()=>{if(this.$refs.library)this.$refs.library.scrollTop=c.scroll})},
 closeVideo(){this.closeContent()},closeReader(){this.closeContent()},
 stepVideo(delta){if(!this.queueIds.length)return;const n=this.queueAt+delta;if(n<0)return;if(n>=this.queueIds.length){this.panel='queue-end';return}this.queueAt=n;this.activateVideo(this.queueIds[n])},
 chooseQueue(id){this.queueAt=this.queueIds.indexOf(id);this.activateVideo(id)},
 setQueueOrder(order){if(order===this.queueOrder)return;const current=this.video.id;this.queueOrder=order;if(order==='随机'){const other=this.queueOriginal.filter(id=>id!==current&&!this.trashIds.includes(id));for(let i=other.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[other[i],other[j]]=[other[j],other[i]]}this.queueIds=[current,...other];this.queueAt=0}else{this.queueIds=this.queueOriginal.filter(id=>!this.trashIds.includes(id));this.queueAt=this.queueIds.indexOf(current)}},
 videoSwipe(e){if(this.videoGesture===null)return;const dy=e.clientY-this.videoGesture;this.videoGesture=null;if(Math.abs(dy)>65)this.stepVideo(dy<0?1:-1)},
 openPack(id){const p=this.packs.find(x=>x.id===id&&!this.trashIds.includes(x.id));if(!p)return;if(this.screen!=='reader'){this.packQuick=false;this.returnContext=this.sourceContext();const list=this.tab==='recent'?this.recentItems:this.filteredItems;this.queueIds=list.some(i=>i.id===id)?list.map(i=>i.id):[id];this.queueOriginal=[...this.queueIds];this.queueLabel=this.tab==='recent'?'最近 · 最近阅读的图包':(this.fromTags?'标签结果':'媒体库')+' · '+this.scopeLabel}
  this.queueAt=this.queueIds.indexOf(id);this.selected=this.packs.findIndex(x=>x.id===id);this.page=Math.min(this.progress[id]??0,p.pages.length-1);this.mode=this.preferences[id]?.mode||this.defaultMode;this.direction=this.preferences[id]?.direction||'ltr';this.gap=this.preferences[id]?.gap||false;this.screen='reader';this.panel='';this.controls=true;this.zoom=false;this.failedImage=false;this.chosen=[];this.targetId=id;this.tagKind='pack';this.last=id;this.progress[id]=this.page;this.touchHistory(id);this.$nextTick(()=>this.scrollToPage())},
 movePack(delta){const id=this.queueIds[this.queueAt+delta];if(id)this.openPack(id);else this.panel='finished'},
 changeMode(m){this.mode=m;this.zoom=false;this.preferences[this.pack.id]={mode:m,direction:this.direction,gap:this.gap,fit:this.fit};this.save();this.$nextTick(()=>this.scrollToPage())},
 editTags(id){this.targetId=id||(this.screen==='reader'?this.pack.id:this.video.id);this.tagKind=this.chosen.length?this.kind:(this.targetId.startsWith('v-')?'video':'pack');this.draftTags=this.chosen.length?[]:[...this.tagTargets[0].tags];this.tagInput='';this.panel='tags'},
 addTag(){const t=this.tagInput.trim();if(t&&!this.draftTags.includes(t))this.draftTags.push(t);this.tagInput=''},
 get editTagOptions(){return [...new Set([...this.allTags,...this.draftTags])]},
 saveTags(){this.addTag();const before=this.tagTargets.map(i=>[i.id,[...i.tags]]),catalog=[...this.allTags];this.tagTargets.forEach(i=>i.tags=this.chosen.length?[...new Set([...i.tags,...this.draftTags])]:[...this.draftTags]);this.tagCatalog[this.tagKind]=[...new Set([...this.allTags,...this.draftTags])];if(!this.save()){before.forEach(([id,t])=>[...this.packs,...this.videos].find(i=>i.id===id).tags=t);this.tagCatalog[this.tagKind]=catalog;return}this.panel='';this.toast((this.tagKind==='video'?'视频':'整包')+'标签已保存')},
 tagCount(t){return this.itemsOfKind.filter(i=>i.tags.includes(t)).length},
 manageTag(t){this.editingTagKind=this.kind;this.editingTag=t;this.tagRename=t;this.panel='rename'},
 createTag(){const t=this.createName.trim();if(!t)return;if(this.currentCatalog.includes(t)){this.error='此类型已有同名标签。';return}this.tagCatalog[this.kind].push(t);if(!this.save()){this.tagCatalog[this.kind].pop();return}this.panel='';this.createName='';this.toast(this.typeName+'标签已创建')},
 renameTag(){const t=this.tagRename.trim(),kind=this.editingTagKind;if(!t)return;if(t!==this.editingTag&&this.tagCatalog[kind].includes(t)){this.error='此类型已有同名标签，请换一个名称。';return}this.mutateTag(t)},
 mutateTag(newName){const kind=this.editingTagKind,oldName=this.editingTag,items=kind==='video'?this.videos:this.packs;const catalog=[...this.tagCatalog[kind]],old=items.map(i=>[...i.tags]);this.tagCatalog[kind]=catalog.flatMap(t=>t===oldName?(newName?[newName]:[]):[t]);items.forEach(i=>i.tags=i.tags.flatMap(t=>t===oldName?(newName?[newName]:[]):[t]));if(!this.save()){this.tagCatalog[kind]=catalog;items.forEach((i,n)=>i.tags=old[n]);return}for(const list of [this.scopes[kind].tags,this.tagSelections[kind]]){const n=list.indexOf(oldName);if(n>=0)newName?list.splice(n,1,newName):list.splice(n,1)}this.panel='';this.toast((kind==='video'?'视频':'图包')+'标签已'+(newName?'更新':'移除'))},
 trash(){
  const id=this.deleteId,item=this.allItems.find(i=>i.id===id);if(!item||this.trashIds.includes(id))return;
  const before=[...this.trashIds];this.trashIds.push(id);if(!this.save()){this.trashIds=before;return}
  const wasQuick=this.screen==='reader'&&this.packQuick;
  this.lastRemoved={id,at:this.queueAt,ids:[...this.queueIds],original:[...this.queueOriginal],label:this.queueLabel,screen:this.screen,packQuick:this.packQuick,origin:this.returnContext?{...this.returnContext}:null};
  this.queueIds=this.queueIds.filter(x=>x!==id);this.queueOriginal=this.queueOriginal.filter(x=>x!==id);this.panel='';
  let ended=false;
  if(this.screen==='video'){if(this.queueIds.length){this.queueAt=Math.min(this.queueAt,this.queueIds.length-1);this.activateVideo(this.queueIds[this.queueAt])}else this.closeContent()}
  else if(this.screen==='reader'){const next=this.queueIds[this.queueAt];if(wasQuick&&next)this.openPack(next);else{ended=wasQuick;this.closeContent()}}
  this.toast(item.type==='pack'?'「'+item.title+'」已移入回收站'+(ended?'，已到本次末尾':''):'已移入回收站，源文件保留');
 },
 restore(id){const old=[...this.trashIds];this.trashIds=this.trashIds.filter(x=>x!==id);if(!this.save()){this.trashIds=old;return}this.toast('已恢复');this.lastRemoved=null},
 undoTrash(){
  if(!this.lastRemoved)return;const removed=this.lastRemoved,old=[...this.trashIds];this.trashIds=this.trashIds.filter(x=>x!==removed.id);if(!this.save()){this.trashIds=old;return}
  if(['video','reader'].includes(removed.screen)){this.queueIds=[...removed.ids];this.queueOriginal=[...removed.original];this.queueAt=removed.at;this.queueLabel=removed.label;this.returnContext=removed.origin;
   if(removed.screen==='video')this.activateVideo(removed.id);else{this.screen='reader';this.packQuick=removed.packQuick;this.openPack(removed.id)}
  }
  this.lastRemoved=null;this.toast('已撤销移除');
 },
 exportData(){if(!this.save())return;const url=URL.createObjectURL(new Blob([JSON.stringify({schema:'library-first-v3',data:this.snapshotData()},null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='留白-媒体库原型备份.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)},
 async importData(e){try{const f=e.target.files[0];if(!f)return;const x=JSON.parse(await f.text());if(x.schema!=='library-first-v3'||!x.data.tags||!['video','pack'].every(k=>Array.isArray(x.data.tagCatalog?.[k])&&x.data.tagCatalog[k].every(t=>typeof t==='string'))||!Array.isArray(x.data.history)||!Array.isArray(x.data.trashIds))throw Error();for(const ts of Object.values(x.data.tags))if(!Array.isArray(ts)||ts.some(t=>typeof t!=='string'))throw Error();this.pendingImport=x.data;this.panel='restoreBackup'}catch{this.error='备份格式不正确，请选择此版本导出的备份。'}finally{e.target.value=''}},
 confirmRestore(){try{if(qs.get('scenario')==='storage-failure')throw Error();localStorage.setItem(LIBRARY_STORE,JSON.stringify(this.pendingImport));location.href='app.html?state=settings'}catch{this.error='恢复失败，原有数据保留。'}},
 key(e){if(/INPUT|TEXTAREA|SELECT/.test(e.target.tagName))return;if(e.key==='Escape'){if(this.panel)this.panel='';else if(this.screen!=='home')this.closeContent();else if(this.fromTags){this.fromTags=false;this.tab='tags'}return}if(this.panel)return;if(this.screen==='reader'&&this.mode==='horizontal'){if(e.key==='ArrowRight'){e.preventDefault();this.advance(this.direction==='rtl'?-1:1)}if(e.key==='ArrowLeft'){e.preventDefault();this.advance(this.direction==='rtl'?1:-1)}}if(this.screen==='video'&&['ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();this.stepVideo(e.key==='ArrowDown'?1:-1)}}
}));
