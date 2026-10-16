const STORAGE_KEY = 'video-viewer-paper-p2-v1';
const MEDIA = '../p1/assets/';
const clone = value => JSON.parse(JSON.stringify(value));
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
const initialData = () => ({
  videos: [
    {id:'v1',name:'花间微风_02.mp4',path:'/videos/收集/花草/竖版/花间微风_02.mp4',root:'r1',orientation:'portrait',duration:5,type:'MP4',tags:['自然','花卉'],asset:'flower-portrait',status:'available'},
    {id:'v2',name:'庭院片段_01.mp4',path:'/videos/收集/花草/横版/庭院片段_01.mp4',root:'r1',orientation:'landscape',duration:5,type:'MP4',tags:['自然','花卉','庭院'],asset:'flower-landscape',status:'available'},
    {id:'v3',name:'花苞近景_03.mp4',path:'/videos/收集/花草/竖版/花苞近景_03.mp4',root:'r1',orientation:'portrait',duration:5,type:'MP4',tags:['自然','微距'],asset:'flower-portrait',frame:'portrait-late',status:'available'},
    {id:'v4',name:'公园花草_04.mp4',path:'/videos/旅行/公园/公园花草_04.mp4',root:'r1',orientation:'landscape',duration:5,type:'MP4',tags:['自然','花卉','散步'],asset:'flower-landscape',frame:'landscape-late',status:'available'},
    {id:'v5',name:'庭院随拍_05.mp4',path:'/collection/新收藏/庭院随拍_05.mp4',root:'r2',orientation:'portrait',duration:5,type:'MP4',tags:['庭院'],asset:'flower-portrait',frame:'portrait-early',status:'available'},
    {id:'v6',name:'植物细节_06.mp4',path:'/collection/新收藏/植物细节_06.mp4',root:'r2',orientation:'landscape',duration:5,type:'MP4',tags:['自然','微距'],asset:'flower-landscape',frame:'landscape-early',status:'available'},
    {id:'v7',name:'去年花开_07.mp4',path:'/videos/收集/去年花开_07.mp4',root:'r1',orientation:'portrait',duration:5,type:'MP4',tags:['自然','花卉'],asset:'flower-portrait',status:'missing'},
    {id:'v8',name:'窗边花草_08.mp4',path:'/videos/收集/窗边花草_08.mp4',originalPath:'/videos/收集/窗边花草_08.mp4',root:'r1',orientation:'landscape',duration:5,type:'MP4',tags:['庭院'],asset:'flower-landscape',status:'trash'}
  ],
  tags:['自然','花卉','庭院','微距','散步'],
  roots:[{id:'r1',name:'视频收藏',path:'/videos',status:'available',lastScan:'今天 09:20'},{id:'r2',name:'收集目录',path:'/collection',status:'available',lastScan:'今天 09:20'}],
  filters:[], attrs:{orientation:'',duration:'',type:''}, folder:'', playMode:'random',
  round:['v1','v3','v2','v5','v4','v6'], index:0,
  connection:{address:'192.168.1.20',port:'8760',connected:true}, lastDelete:null, lastDeleteRound:null
});

window.videoLibrary = () => ({
  ...initialData(), page:'browse', cleanup:false, panel:'', menu:false,
  busy:false, error:'', formError:'', notice:'', selected:[], selecting:false,
  search:'', tagSearch:'', folderCursor:'', folderReturnTo:'', editId:'', form:{}, draftTags:[], batchAction:'add',
  paused:true, time:0, duration:5, speed:1, mediaError:false, fullscreen:false,
  pointer:null, swiped:false, lastWheel:0, roundEnded:false,
  draftAttrs:{}, reviewTags:[], pendingBackup:null, restoreMaps:[],
  restoreChecked:false, confirmKind:'', confirmIds:[], confirmText:'',
  connectionForm:{address:'192.168.1.20',port:'8760',passphrase:'demo'},
  fault:new URLSearchParams(location.search).get('scenario') || '', returnPage:'settings',
  get pageTitle(){ return ({browse:this.cleanup?'快速整理':'浏览',library:'视频库',tags:'标签',settings:'设置',connection:'连接',roots:'媒体目录',trash:'回收站',backup:'备份与恢复'})[this.page] || '浏览'; },
  get mainPage(){return ['browse','library','tags','settings'].includes(this.page);},
  get isMedia(){return ['browse','library'].includes(this.page);},
  get candidates(){return this.videos.filter(v=>this.matches(v));},
  get current(){const v=this.videos.find(v=>v.id===this.round[this.index]);return v && this.matches(v) ? v : null;},
  get libraryVideos(){return this.candidates.filter(v=>v.name.toLowerCase().includes(this.search.toLowerCase()));},
  get visibleTags(){return [...new Set([...(this.current?.tags || []),...this.filters])];},
  get trashVideos(){return this.videos.filter(v=>v.status==='trash');},
  get tagResults(){return this.tags.filter(t=>t.includes(this.tagSearch));},
  get missingVideos(){return this.videos.filter(v=>v.status==='missing');},
  get folderChildren(){
    if (!this.folderCursor) return this.roots.map(r=>({path:r.path,name:r.name,root:true,unavailable:r.status!=='available'}));
    const dirs=new Set();
    const sources=this.videos.map(v=>v.path.substring(0,v.path.lastIndexOf('/')));
    for(const p of sources){if(p.startsWith(this.folderCursor+'/')) dirs.add(this.folderCursor+'/'+p.slice(this.folderCursor.length+1).split('/')[0]);}
    return [...dirs].sort().map(p=>({path:p,name:p.split('/').pop()}));
  },
  get breadcrumbs(){
    if (!this.folderCursor) return [];
    const root=this.roots.find(r=>this.under(this.folderCursor,r.path));
    if(!root)return [];
    const crumbs=[{name:root.name,path:root.path}];
    let prefix=root.path;
    for(const part of this.folderCursor.slice(root.path.length).split('/').filter(Boolean)){prefix+='/'+part;crumbs.push({name:part,path:prefix});}
    return crumbs;
  },
  get confirmTitle(){return ({permanent:'永久删除这些视频？',tag:'删除这个标签？',reset:'重置演示数据？',restore:'替换管理数据？'})[this.confirmKind] || '确认操作';},
  poster(v){if(!v)return '';const frame=v.frame||initialData().videos.find(item=>item.id===v.id)?.frame;return ['portrait-late','portrait-early','landscape-late','landscape-early'].includes(frame)?'assets/'+frame+'.jpg':MEDIA+v.asset+'.jpg';},
  player(){return document.querySelector('#player');},
  under(path,folder){return path===folder || path.startsWith(folder+'/');},
  matches(v){
    return v.status==='available' && this.roots.some(r=>r.id===v.root && r.status==='available') &&
      (!this.folder || this.under(v.path,this.folder)) && this.filters.every(t=>v.tags.includes(t)) &&
      (!this.attrs.orientation || this.attrs.orientation===v.orientation) &&
      (!this.attrs.type || this.attrs.type===v.type) &&
      (!this.attrs.duration || (this.attrs.duration==='short' ? v.duration<=10 : v.duration>10));
  },
  init(){
    if(new URLSearchParams(location.search).get('reset')==='1'){localStorage.removeItem(STORAGE_KEY);const url=new URL(location.href);url.searchParams.delete('reset');history.replaceState(null,'',url);}
    try{const saved=JSON.parse(localStorage.getItem(STORAGE_KEY)||'null');if(saved?.version===1)this.assignData(saved.data);}catch{this.error='无法读取保存的数据，可以在设置中重试或重置。';}
    const params=new URLSearchParams(location.search), target=params.get('page'),state=params.get('state');
    if(target && ['browse','library','tags','settings','connection','roots','trash','backup'].includes(target))this.page=target;
    if(this.fault==='empty'){this.videos=[];this.round=[];this.page='library';}
    if(this.fault==='offline'){this.connection.connected=false;this.page='connection';}
    if(this.fault==='root-unavailable')this.roots[1].status='unavailable';
    this.reconcile();
    if(state==='landscape'){const i=this.round.findIndex(id=>this.videos.find(v=>v.id===id)?.orientation==='landscape');if(i>=0)this.index=i;}
    if(state==='folders'){this.folderCursor='/videos/收集';this.panel='folders';}
    if(state==='filtered'){this.filters=['花卉'];this.newRound(false);}
    this.connectionForm.address=this.connection.address;this.connectionForm.port=this.connection.port;
    if(!this.connection.connected)this.page='connection';
    this.$nextTick(()=>this.loadVideo(false));
    document.addEventListener('fullscreenchange',()=>{if(!document.fullscreenElement){this.fullscreen=false;screen.orientation?.unlock?.();}});
    if(this.fault==='loading'){this.busy=true;wait(1500).then(()=>this.busy=false);}
  },
  pack(){const data={};for(const key of Object.keys(initialData()))data[key]=clone(this[key]);return data;},
  assignData(data){for(const key of Object.keys(initialData()))if(data[key]!==undefined)this[key]=clone(data[key]);},
  save(){try{if(this.fault==='storage-failure')throw Error('storage');localStorage.setItem(STORAGE_KEY,JSON.stringify({version:1,data:this.pack()}));return true;}catch{this.error='保存失败，刚才的修改未生效。请检查浏览器存储后重试。';return false;}},
  change(fn){const before=this.pack();fn();if(!this.save()){this.assignData(before);return false;}return true;},
  notify(text){this.notice=text;clearTimeout(this.noticeTimer);this.noticeTimer=setTimeout(()=>this.notice='',text==='已移入回收站'?8000:4500);},
  format(value){const s=Math.floor(Number.isFinite(value)?value:0);return String(Math.floor(s/60)).padStart(2,'0')+':'+String(s%60).padStart(2,'0');},
  reconcile(){const id=this.round[this.index];this.round=this.round.filter(id=>this.videos.some(v=>v.id===id&&this.matches(v)));this.index=Math.max(0,Math.min(this.round.indexOf(id)>=0?this.round.indexOf(id):this.index,this.round.length-1));},
  newRound(persist=true){
    const ids=[...this.candidates].sort((a,b)=>a.path.localeCompare(b.path,'zh-CN')).map(v=>v.id);
    if(this.playMode==='random')for(let i=ids.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[ids[i],ids[j]]=[ids[j],ids[i]];}
    this.round=ids;this.index=0;this.roundEnded=false;if(persist)this.save();this.$nextTick(()=>this.loadVideo(false));
  },
  navigate(page){this.player()?.pause();this.menu=false;this.panel='';this.error='';this.selected=[];this.selecting=false;this.page=page;if(page==='browse')this.$nextTick(()=>this.loadVideo(false));},
  back(){this.navigate('settings');},
  loadVideo(play=false){
    const el=this.player();if(!el)return;el.pause();this.time=0;this.mediaError=false;this.paused=true;
    if(!this.current){el.removeAttribute('src');el.load();return;}
    el.src=MEDIA+this.current.asset+'.mp4';el.playbackRate=this.speed;el.load();
    if(play && this.page==='browse')el.play().catch(()=>this.paused=true);
  },
  tap(){if(this.swiped){this.swiped=false;return;}const p=this.player();if(p.paused)p.play().catch(()=>this.mediaError=true);else p.pause();},
  step(delta){
    if(this.page!=='browse'||this.panel||this.menu||!this.round.length)return;
    this.reconcile();const next=this.index+delta;
    if(next<0){this.notify('已经是第一条');return;}
    if(next>=this.round.length){this.roundEnded=true;this.notify('本轮已看完，可在更多中重新开始');return;}
    if(this.change(()=>{this.index=next;this.roundEnded=false;}))this.$nextTick(()=>this.loadVideo(true));
  },
  pointerStart(e){if(this.panel||this.menu||e.target.closest('.controls,.wide-button,.cleanup-delete,.fullscreen-exit'))return;this.pointer={x:e.clientX,y:e.clientY};this.swiped=false;},
  pointerEnd(e){if(!this.pointer)return;const dx=e.clientX-this.pointer.x,dy=e.clientY-this.pointer.y;this.pointer=null;if(Math.abs(dy)>55&&Math.abs(dy)>Math.abs(dx)*1.3){this.swiped=true;this.step(dy<0?1:-1);}},
  wheel(e){if(this.menu||this.panel||e.target.closest('.controls')||Math.abs(e.deltaY)<25||Date.now()-this.lastWheel<650)return;this.lastWheel=Date.now();this.step(e.deltaY>0?1:-1);},
  setMode(mode){if(this.change(()=>{this.playMode=mode;this.newRound(false);})){this.closePanel();this.notify(mode==='random'?'已切换随机播放':'已切换顺序播放');}},
  openFolder(){this.folderReturnTo=this.panel==='review-filters'?'review-filters':'';this.folderCursor=this.folder;this.openPanel('folders');},
  enterFolder(node){if(node.unavailable){this.formError='这个媒体目录暂时无法访问，原有记录仍保留。';return;}this.formError='';this.folderCursor=node.path;},
  useFolder(){if(this.change(()=>{this.folder=this.folderCursor;this.newRound(false);})){this.selected=[];const returnTo=this.folderReturnTo;this.folderReturnTo='';this.closePanel();if(returnTo)this.$nextTick(()=>this.openPanel(returnTo));}},
  folderCount(path){return this.videos.filter(v=>v.status==='available'&&this.under(v.path,path)).length;},
  setFilters(tags,attrs=this.attrs){if(this.change(()=>{this.filters=[...tags];this.attrs=clone(attrs);this.newRound(false);})){this.selected=[];}},
  toggleFilter(tag){this.setFilters(this.filters.includes(tag)?this.filters.filter(t=>t!==tag):[...this.filters,tag]);},
  openAttributes(){this.draftAttrs=clone(this.attrs);this.openPanel('attributes');},
  startCleanup(){this.cleanup=true;this.navigate('browse');},
  stopCleanup(){this.cleanup=false;this.menu=false;},
  openReviewFilters(){this.reviewTags=[...this.filters];this.draftAttrs=clone(this.attrs);this.openPanel('review-filters');},
  openVideo(video){if(!this.round.includes(video.id))this.newRound(false);this.index=this.round.indexOf(video.id);this.save();this.navigate('browse');this.$nextTick(()=>this.loadVideo(true));},
  select(id){this.selected=this.selected.includes(id)?this.selected.filter(x=>x!==id):[...this.selected,id];},
  tagCount(tag){return this.videos.filter(v=>v.tags.includes(tag)&&v.status!=='trash').length;},
  openTagEditor(ids){this.editIds=ids || (this.selected.length?[...this.selected]:this.current?[this.current.id]:[]);this.draftTags=this.editIds.length===1?[...this.videos.find(v=>v.id===this.editIds[0]).tags]:[];this.batchAction='add';this.openPanel('tag-edit');},
  saveTags(){
    if(this.change(()=>{for(const v of this.videos.filter(v=>this.editIds.includes(v.id))){v.tags=this.editIds.length===1?[...this.draftTags]:this.batchAction==='add'?[...new Set([...v.tags,...this.draftTags])]:v.tags.filter(t=>!this.draftTags.includes(t));}this.reconcile();})){this.closePanel();this.notify('标签已更新');this.loadVideo(false);}
  },
  openTagForm(name=''){this.editId=name;this.form={name};this.openPanel('tag-form');},
  saveTag(){const name=this.form.name.trim();if(!name){this.formError='请输入标签名称';return;}if(this.tags.includes(name)&&name!==this.editId){this.formError='已有同名标签';return;}
    if(this.change(()=>{if(this.editId){this.tags=this.tags.map(t=>t===this.editId?name:t);this.videos.forEach(v=>v.tags=v.tags.map(t=>t===this.editId?name:t));this.filters=this.filters.map(t=>t===this.editId?name:t);}else this.tags.push(name);})){this.closePanel();this.notify('标签已保存');}},
  askDeleteTag(tag){this.confirmKind='tag';this.confirmText='只解除「'+tag+'」与视频的关联，不删除文件。';this.editId=tag;this.openPanel('confirm');},
  async removeVideo(ids){
    if(!ids.length)return;this.menu=false;this.busy=true;this.error='';await wait(360);
    if(this.fault==='write-failure'){this.busy=false;this.error='移动失败：目录没有写入权限，视频仍在原位置。';return;}
    const id=ids[ids.length-1];
    const ok=this.change(()=>{this.lastDeleteRound={round:[...this.round],index:this.index};for(const v of this.videos.filter(v=>ids.includes(v.id))){v.originalPath=v.path;v.status='trash';v.deletedAt=new Date().toISOString();}this.lastDelete=id;this.reconcile();});
    this.busy=false;if(ok){this.selected=[];this.notify('已移入回收站');this.loadVideo(this.page==='browse');}
  },
  restore(ids){
    const restoreVideos=this.videos.filter(v=>ids.includes(v.id)&&v.status==='trash');
    if(this.fault==='conflict'||restoreVideos.some(v=>this.videos.some(other=>other.id!==v.id&&other.status==='available'&&other.path===(v.originalPath||v.path)))){this.error='恢复失败：原位置已有同名文件，没有覆盖。';return;}
    if(this.change(()=>{for(const v of restoreVideos){v.status='available';v.path=v.originalPath||v.path;}if(ids.includes(this.lastDelete))this.lastDelete=null;})){this.selected=[];this.notify('已恢复，标签保留');}
  },
  undo(){if(!this.lastDelete)return;const id=this.lastDelete,snapshot=this.lastDeleteRound?clone(this.lastDeleteRound):null;this.restore([id]);if(!this.lastDelete){if(snapshot){this.round=snapshot.round.filter(id=>this.videos.some(v=>v.id===id&&this.matches(v)));}else this.newRound(false);const i=this.round.indexOf(id);this.index=Math.max(0,i);this.roundEnded=false;this.lastDeleteRound=null;this.save();this.loadVideo(false);}},
  askPermanent(){this.confirmKind='permanent';this.confirmIds=[...this.selected];this.confirmText='将永久删除所选 '+this.confirmIds.length+' 个视频，无法撤销。';this.openPanel('confirm');},
  confirm(){
    if(this.confirmKind==='reset'){localStorage.removeItem(STORAGE_KEY);location.href=location.pathname;return;}
    if(this.confirmKind==='permanent'){if(this.fault==='write-failure'){this.formError='删除失败：目录没有写入权限';return;}if(!this.change(()=>{this.videos=this.videos.filter(v=>!(this.confirmIds.includes(v.id)&&v.status==='trash'));if(this.confirmIds.includes(this.lastDelete))this.lastDelete=null;}))return;this.selected=[];this.notify('已永久删除所选视频');}
    if(this.confirmKind==='tag'){if(!this.change(()=>{const active=this.filters.includes(this.editId);this.tags=this.tags.filter(t=>t!==this.editId);this.videos.forEach(v=>v.tags=v.tags.filter(t=>t!==this.editId));this.filters=this.filters.filter(t=>t!==this.editId);if(active)this.newRound(false);else this.reconcile();}))return;}
    this.closePanel();
  },
  openRoot(root=null){this.editId=root?.id||'';this.form=root?clone(root):{name:'',path:''};this.openPanel('root-form');},
  saveRoot(){const path=this.form.path.trim().replace(/\/+$/,'');if(!this.form.name.trim()||!path.startsWith('/')||path==='/'||path.includes('..')){this.formError='请填写名称和具体的挂载目录路径';return;}if(this.roots.some(r=>r.id!==this.editId&&r.path===path)){this.formError='该目录已经接入';return;}if(this.change(()=>{if(this.editId)Object.assign(this.roots.find(r=>r.id===this.editId),{name:this.form.name.trim(),path});else this.roots.push({id:'r'+Date.now(),name:this.form.name.trim(),path,status:'available',lastScan:'尚未扫描'});})){this.closePanel();}},
  async scan(){
    this.busy=true;this.error='';await wait(750);
    if(this.fault==='root-unavailable'){this.busy=false;this.error='收集目录暂不可用，保留已有视频及标签记录。';return;}
    if(this.change(()=>{this.roots.forEach(r=>r.lastScan='刚刚');if(!this.videos.some(v=>v.id==='new-scan'))this.videos.push({id:'new-scan',name:'新收集片段_09.mp4',path:'/collection/新收藏/新收集片段_09.mp4',root:'r2',orientation:'landscape',duration:5,type:'MP4',tags:[],asset:'flower-landscape',status:'available'});})){this.notify('刷新完成，新增内容将在下一轮播放');}this.busy=false;
  },
  async connect(){
    const f=this.connectionForm;if(!f.address.trim()||!/^\d+$/.test(f.port)||Number(f.port)<1||Number(f.port)>65535){this.error='请填写服务地址和 1–65535 之间的端口';return;}
    this.busy=true;this.error='';await wait(500);
    if(this.fault==='offline'||f.address.includes('unreachable')){this.error='连接不到服务，请检查地址和局域网连接。';this.busy=false;return;}
    if(f.passphrase!=='demo'){this.error='口令不正确，请重新输入。';this.busy=false;return;}
    if(this.change(()=>this.connection={address:f.address.trim(),port:f.port,connected:true}))this.navigate('browse');this.busy=false;
  },
  exportBackup(){const payload={format:'video-viewer-management',version:1,createdAt:new Date().toISOString(),data:this.pack()};delete payload.data.connection;const blob=new Blob([JSON.stringify(payload,null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='video-viewer-backup-'+new Date().toISOString().slice(0,10)+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);this.notify('已导出管理数据备份');},
  validateBackup(value){
    if(value?.format!=='video-viewer-management'||value.version!==1)throw Error('备份版本或格式不兼容');
    const d=value.data;if(!d||!Array.isArray(d.videos)||!Array.isArray(d.tags)||!Array.isArray(d.roots)||!Array.isArray(d.round)||!Array.isArray(d.filters)||!d.attrs)throw Error('备份内容不完整');
    if(d.tags.some(t=>typeof t!=='string')||new Set(d.tags).size!==d.tags.length||d.videos.some(v=>!v.id||typeof v.name!=='string'||typeof v.path!=='string'||!Array.isArray(v.tags)||!['flower-portrait','flower-landscape'].includes(v.asset)||!['available','trash','missing'].includes(v.status))||d.roots.some(r=>!r.id||typeof r.path!=='string'||!r.path.startsWith('/')))throw Error('备份数据校验失败');
    return d;
  },
  async importBackup(event){const file=event.target.files?.[0];if(!file)return;this.error='';try{if(file.size>5*1024*1024)throw Error('备份超过 5 MB');const parsed=JSON.parse(await file.text());this.validateBackup(parsed);this.pendingBackup=parsed;this.restoreMaps=parsed.data.roots.map(r=>({id:r.id,from:r.path,to:r.path}));this.restoreChecked=false;this.openPanel('restore');}catch(e){this.error=e instanceof SyntaxError?'备份文件不是有效的 JSON':e.message;}finally{event.target.value='';}},
  async restoreBackup(){
    if(!this.restoreChecked){this.formError='请确认替换现有管理数据';return;}
    if(this.restoreMaps.some(m=>!m.to.startsWith('/')||m.to.includes('..'))){this.formError='请检查媒体目录映射';return;}
    this.busy=true;await wait(500);
    try{this.validateBackup(this.pendingBackup);const incoming=clone(this.pendingBackup.data);for(const map of this.restoreMaps){incoming.roots.find(r=>r.id===map.id).path=map.to;for(const v of incoming.videos.filter(v=>v.root===map.id)){if(this.under(v.path,map.from))v.path=map.to+v.path.slice(map.from.length);if(v.originalPath&&this.under(v.originalPath,map.from))v.originalPath=map.to+v.originalPath.slice(map.from.length);}if(incoming.folder&&this.under(incoming.folder,map.from))incoming.folder=map.to+incoming.folder.slice(map.from.length);}
      const before=this.pack();localStorage.setItem(STORAGE_KEY+'-before-restore',JSON.stringify({version:1,data:before}));
      if(this.fault==='write-failure')throw Error('恢复未完成，原有管理数据保持不变');
      if(this.change(()=>{this.assignData(incoming);this.reconcile();})){this.closePanel();this.notify('管理数据已恢复');}
    }catch(e){this.formError=e.message;}this.busy=false;
  },
  async enterFullscreen(){
    const stage=document.querySelector('.viewer');this.fullscreen=true;
    try{if(stage.requestFullscreen)await stage.requestFullscreen();}catch{/* CSS viewport fallback stays usable. */}
    try{await screen.orientation?.lock?.('landscape');}catch{/* Desktop and unsupported browsers use the landscape layout. */}
    this.player()?.play().catch(()=>this.paused=true);
  },
  async exitFullscreen(){this.fullscreen=false;try{if(document.fullscreenElement)await document.exitFullscreen();screen.orientation?.unlock?.();}catch{}},
  openPanel(name){this.menu=false;this.panel=name;this.formError='';if(this.notice!=='已移入回收站')this.notice='';this.player()?.pause();this.focusReturn=document.activeElement;this.$nextTick(()=>document.querySelector('.sheet input:not([type=checkbox]),.sheet button')?.focus());},
  closePanel(){if(this.panel==='folders'&&this.folderReturnTo){this.panel=this.folderReturnTo;this.folderReturnTo='';this.formError='';return;}this.panel='';this.formError='';this.$nextTick(()=>{if(this.focusReturn?.isConnected)this.focusReturn.focus();});},
  trapFocus(event){const list=[...event.currentTarget.querySelectorAll('button,input,select,a[href]')].filter(el=>!el.disabled&&el.getClientRects().length);const first=list[0],last=list[list.length-1];if(event.shiftKey&&document.activeElement===first){event.preventDefault();last?.focus();}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first?.focus();}}
});
