const PRODUCT_STORE='media-product-v2-'+VARIANT;
const VIDEO_ITEMS=[
 {id:'v-portrait',type:'video',title:'水边的花',author:'自然随拍',folder:'短视频 / 竖屏',duration:'0:05',cover:'/_shared/media/flower-portrait.jpg',src:'/_shared/media/flower-portrait.mp4',tags:['户外','自然']},
 {id:'v-landscape',type:'video',title:'风里的花园',author:'自然随拍',folder:'短视频 / 横屏',duration:'0:05',cover:'/_shared/media/flower-landscape.jpg',src:'/_shared/media/flower-landscape.mp4',tags:['户外','喜欢']}
];
window.productApp=()=>Object.defineProperties(packApp(),Object.getOwnPropertyDescriptors({
 variant:VARIANT,tab:VARIANT==='b'?'library':'browse',kind:VARIANT==='b'?'all':'video',channel:'video',screen:'home',panel:'',
 videos:structuredClone(VIDEO_ITEMS),videoIndex:0,videoPlaying:false,videoTime:0,videoDuration:0,videoSpeed:1,videoControls:true,videoError:false,videoOrder:'顺序',quick:false,videoGesture:null,
 tagResults:false,search:'',searchOpen:false,filters:[],statusFilter:'全部',sort:'名称',multi:false,chosen:[],targetId:'summer',trashIds:[],history:['summer','v-portrait'],
 allTags:['和服','户外','白裙','角色','喜欢','自然'],connection:'http://nas.local:8000',connectionDraft:'',connectionTested:false,defaultMode:'horizontal',rootEnabled:{video:true,pack:true},tagRename:'',editingTag:'',deleteId:'',
 channelState:{video:'browse',pack:'library'},returnKind:'pack',returnChannel:'pack',returnTab:'library',savedScroll:0,
 get allItems(){return [...this.videos,...this.packs.map(p=>({...p,type:'pack',cover:p.pages[0]}))]},
 get available(){return this.allItems.filter(i=>!this.trashIds.includes(i.id)&&this.rootEnabled[i.type])},
 get filteredItems(){return this.available.filter(i=>(this.kind==='all'||i.type===this.kind)&&this.filters.every(t=>i.tags.includes(t))&&(!this.search||`${i.title} ${i.author} ${i.folder}`.includes(this.search))&&(this.statusFilter!=='未读'||(i.type==='pack'&&this.progress[i.id]===undefined))&&(this.statusFilter!=='在读'||(i.type==='pack'&&this.progress[i.id]!==undefined&&this.progress[i.id]<i.pages.length-1))).sort((a,b)=>this.sort==='名称'?a.title.localeCompare(b.title,'zh-CN'):this.allItems.indexOf(b)-this.allItems.indexOf(a))},
 get nextPack(){const list=this.packs.filter(p=>!this.trashIds.includes(p.id)&&this.rootEnabled.pack&&this.filters.every(t=>p.tags.includes(t)));const n=list.findIndex(p=>p.id===this.pack.id);return list[(n+1)%list.length]||this.pack},
 get recent(){return this.packs.find(p=>p.id===this.last&&!this.trashIds.includes(p.id))||this.packs.find(p=>!this.trashIds.includes(p.id))||this.packs[0]},
 get recentItems(){return this.history.map(id=>this.available.find(i=>i.id===id)).filter(Boolean)},
 get video(){return this.videos[this.videoIndex]},
 get tagTargets(){const ids=this.chosen.length?this.chosen:[this.targetId];return [...this.packs,...this.videos].filter(p=>ids.includes(p.id))},
 get navItems(){return this.variant==='a'?[['browse','浏览','play'],['library','媒体库','grid'],['tags','标签','tag'],['settings','设置','settings']]:this.variant==='b'?[['library','媒体库','grid'],['recent','最近','history'],['tags','标签','tag'],['settings','设置','settings']]:[['video','视频','play'],['pack','图包','book'],['tags','标签','tag'],['settings','设置','settings']]},
 get activeNav(){if(this.tagResults)return 'tags';if(this.variant==='b'&&this.tab==='browse')return 'library';return this.variant==='c'&&['browse','library'].includes(this.tab)?this.channel:this.tab},
 get title(){if(this.tagResults)return '标签筛选';if(this.variant==='b'&&this.tab==='browse')return this.kind==='video'?'连续播放':'逐包看';return this.variant==='c'&&['browse','library'].includes(this.tab)?(this.channel==='video'?'视频':'图包'):({browse:'浏览',library:'媒体库',recent:'最近看过',tags:'标签',settings:'设置'})[this.tab]},
 get sheetTitle(){return ({tags:this.chosen.length?'批量标签':this.targetId.startsWith('v-')?'视频标签':'整包标签','reader-settings':'阅读设置',overview:'页码总览',more:'更多操作','pack-more':'图包操作',folder:'目录范围',filter:'筛选媒体',finished:'读完本包',details:'图包详情',connection:'服务器连接',roots:'媒体目录',defaults:'默认阅读方式',trash:'回收站',backup:'备份与恢复',rename:'管理标签',delete:'移入回收站',permanent:'永久移除记录'})[this.panel]||'设置'},
 init(){
   if(qs.has('reset'))localStorage.removeItem(PRODUCT_STORE);
   try{const d=qs.has('snapshot')?null:JSON.parse(localStorage.getItem(PRODUCT_STORE)||'null');if(d){for(const k of ['progress','preferences','last','history','trashIds','defaultMode','rootEnabled','allTags','connection'])if(d[k]!==undefined)this[k]=d[k];[...this.packs,...this.videos].forEach(i=>{if(d.tags?.[i.id])i.tags=d.tags[i.id]})}}catch{this.error='本地记录无法读取，仍可浏览媒体。'}
   const state=qs.get('state');
   if(['packs','reader','vertical','readertags','readersettings','library'].includes(state)){this.kind='pack';this.channel='pack';this.tab='library'}
   if(state==='video'){this.kind='video';this.channel='video';this.tab='browse'}
   if(['tags','settings','recent'].includes(state))this.tab=state;
   if(['reader','vertical','readertags','readersettings'].includes(state)){this.openPack('summer');if(state==='vertical')this.changeMode('vertical');if(state==='readertags')this.editTags();if(state==='readersettings')this.panel='reader-settings'}
   this.$watch('panel',p=>{if(p)this.$nextTick(()=>this.$refs.sheet?.focus())});
 },
 save(){try{if(qs.has('snapshot'))return true;if(qs.get('scenario')==='storage-failure')throw Error('storage');localStorage.setItem(PRODUCT_STORE,JSON.stringify({progress:this.progress,preferences:this.preferences,last:this.last,history:this.history,trashIds:this.trashIds,defaultMode:this.defaultMode,rootEnabled:this.rootEnabled,allTags:this.allTags,connection:this.connection,tags:Object.fromEntries([...this.packs,...this.videos].map(i=>[i.id,i.tags]))}));return true}catch{this.error='保存失败，修改尚未写入。请保留当前页面后重试。';return false}},
 touchHistory(id){this.history=[id,...this.history.filter(x=>x!==id)];this.save()},
 nav(n){this.tagResults=false;this.pauseVideo();this.panel='';this.screen='home';this.multi=false;this.chosen=[];this.searchOpen=false;if(this.variant==='c'&&['video','pack'].includes(n)){this.channel=n;this.kind=n;this.tab=this.channelState[n];this.search='';this.filters=[];this.statusFilter='全部'}else this.tab=n;if(this.variant==='a'&&['browse','library'].includes(n)&&this.kind==='all')this.kind=this.channel},
 goTab(t){this.nav(t)},
 setKind(k){this.pauseVideo();this.kind=k;if(k!=='all')this.channel=k;this.statusFilter='全部';this.multi=false;this.chosen=[];this.search='';if(!this.tagResults)this.filters=[]},
 setView(t){this.pauseVideo();this.tab=t;if(this.variant==='c')this.channelState[this.channel]=t;this.chosen=[];this.multi=false},
 browsePacks(){this.screen='home';this.tagResults=false;this.setKind('pack');this.channel='pack';this.tab='browse';this.panel=''},
 browseVideos(){this.screen='home';this.tagResults=false;this.setKind('video');this.channel='video';this.tab='browse';this.panel=''},
 openItem(i){if(this.multi){this.selectPack(i.id);return}i.type==='video'?this.openVideo(i.id):this.openPack(i.id)},
 openPack(id){const n=this.packs.findIndex(p=>p.id===id);if(n<0)return;this.pauseVideo();if(this.screen!=='reader'){this.returnTab=this.tab;this.returnKind=this.kind;this.returnChannel=this.channel;this.savedScroll=this.$refs.library?.scrollTop||0}this.selected=n;this.page=this.progress[id]??0;this.mode=this.preferences[id]?.mode||this.defaultMode;this.direction=this.preferences[id]?.direction||'ltr';this.gap=this.preferences[id]?.gap||false;this.screen='reader';this.panel='';this.controls=true;this.zoom=false;this.failedImage=false;this.chosen=[];this.targetId=id;this.last=id;this.touchHistory(id);this.$nextTick(()=>this.scrollToPage())},
 closeReader(){this.screen='home';this.panel='';this.tab=this.returnTab;this.kind=this.returnKind;this.channel=this.returnChannel;this.$nextTick(()=>{if(this.$refs.library)this.$refs.library.scrollTop=this.savedScroll})},
 openVideo(id){this.returnTab=this.tab;this.returnKind=this.kind;this.returnChannel=this.channel;this.savedScroll=this.$refs.library?.scrollTop||0;this.videoIndex=this.videos.findIndex(v=>v.id===id);this.screen='video';this.panel='';this.videoTime=0;this.videoError=false;this.videoControls=true;this.chosen=[];this.touchHistory(id)},
 closeVideo(){this.pauseVideo();this.screen='home';this.tab=this.returnTab;this.kind=this.returnKind;this.channel=this.returnChannel;this.$nextTick(()=>{if(this.$refs.library)this.$refs.library.scrollTop=this.savedScroll})},
 pauseVideo(){const v=document.querySelector('video');if(v)v.pause();this.videoPlaying=false},
 async toggleVideo(){const v=document.querySelector('video');if(!v)return;if(v.paused){try{await v.play();this.videoPlaying=true;this.touchHistory(this.video.id)}catch{this.videoError=true}}else this.pauseVideo()},
 stepVideo(delta){const list=this.videos.filter(v=>!this.trashIds.includes(v.id)&&this.rootEnabled.video&&this.filters.every(t=>v.tags.includes(t)));if(!list.length)return;this.pauseVideo();let at=list.findIndex(v=>v.id===this.video.id);at=this.videoOrder==='随机'&&list.length>1?(at+1+Math.floor(Math.random()*(list.length-1)))%list.length:(at+delta+list.length)%list.length;this.videoIndex=this.videos.findIndex(v=>v.id===list[at].id);this.videoTime=0;this.videoError=false;this.$nextTick(()=>document.querySelector('video')?.load())},
 videoSwipe(e){if(!this.videoGesture)return;const dy=e.clientY-this.videoGesture;this.videoGesture=null;if(Math.abs(dy)>65)this.stepVideo(dy<0?1:-1)},
 movePack(delta,read=false){const list=this.packs.filter(p=>!this.trashIds.includes(p.id)&&this.rootEnabled.pack&&this.filters.every(t=>p.tags.includes(t)));if(!list.length)return;const n=list.findIndex(p=>p.id===this.pack.id),next=list[(n+delta+list.length)%list.length];this.selected=this.packs.findIndex(p=>p.id===next.id);if(read)this.openPack(next.id)},
 randomPack(){const list=this.packs.filter(p=>p.id!==this.pack.id&&!this.trashIds.includes(p.id)&&this.filters.every(t=>p.tags.includes(t)));if(list.length)this.selected=this.packs.findIndex(p=>p.id===list[Math.floor(Math.random()*list.length)].id)},
 editTags(id){this.targetId=id||(this.screen==='reader'?this.pack.id:this.kind==='video'?this.video.id:this.pack.id);this.draftTags=this.chosen.length?[]:[...this.tagTargets[0].tags];this.tagInput='';this.panel='tags'},
 saveTags(){this.addTag();const before=this.tagTargets.map(i=>[i.id,[...i.tags]]);this.tagTargets.forEach(i=>i.tags=this.chosen.length?[...new Set([...i.tags,...this.draftTags])]:[...this.draftTags]);if(!this.save()){before.forEach(([id,t])=>[...this.packs,...this.videos].find(i=>i.id===id).tags=t);return}this.panel='';this.toast('标签已保存')},
 setFilter(t){this.filters=this.filters.includes(t)?this.filters.filter(x=>x!==t):[...this.filters,t];this.chosen=[]},
 fromTag(t){this.search='';this.filters=[t];this.statusFilter='全部';this.kind='all';this.tagResults=true;this.tab='library';this.chosen=[];this.multi=false},
 tagCount(t,type){return this.available.filter(i=>i.type===type&&i.tags.includes(t)).length},
 manageTag(t){this.editingTag=t;this.tagRename=t;this.panel='rename'},
 renameTag(){const t=this.tagRename.trim();if(!t)return;const before=this.allTags.slice(),items=[...this.packs,...this.videos],old=items.map(i=>[...i.tags]);items.forEach(i=>i.tags=[...new Set(i.tags.map(x=>x===this.editingTag?t:x))]);this.allTags=[...new Set(this.allTags.map(x=>x===this.editingTag?t:x))];if(!this.save()){this.allTags=before;items.forEach((i,n)=>i.tags=old[n]);return}this.panel='';this.toast('标签已更新')},
 askDelete(id){this.deleteId=id;this.panel='delete'},
 trash(){const before=[...this.trashIds];this.trashIds.push(this.deleteId);if(!this.save()){this.trashIds=before;return}this.pauseVideo();this.panel='';if(this.screen==='reader')this.closeReader();else if(this.screen==='video')this.closeVideo();else if(this.kind==='video')this.stepVideo(1);else this.movePack(1);this.toast('已移入回收站，源文件保留')},
 restore(id){const before=[...this.trashIds];this.trashIds=this.trashIds.filter(x=>x!==id);if(!this.save()){this.trashIds=before;return}this.toast('已恢复')},
 openSettings(name){this.panel=name;if(name==='connection'){this.connectionDraft=this.connection;this.connectionTested=false}},
 saveConnection(){try{const u=new URL(this.connectionDraft);if(!['http:','https:'].includes(u.protocol))throw Error()}catch{this.error='请输入完整的 http:// 或 https:// 地址。';return}const old=this.connection;this.connection=this.connectionDraft;if(!this.save()){this.connection=old;return}this.panel='';this.toast('连接地址已保存')},
 setDefault(m){const old=this.defaultMode;this.defaultMode=m;if(!this.save())this.defaultMode=old},
 toggleRoot(type){const old=this.rootEnabled[type];this.rootEnabled[type]=!old;if(!this.save())this.rootEnabled[type]=old},
 exportData(){if(!this.save())return;const data=localStorage.getItem(PRODUCT_STORE)||'{}';const url=URL.createObjectURL(new Blob([JSON.stringify({schema:'media-product-v2',data:JSON.parse(data)},null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='留白-原型备份.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);this.toast('备份已导出')},
 async importData(e){const f=e.target.files[0];if(!f)return;try{const x=JSON.parse(await f.text());if(x.schema!=='media-product-v2'||!x.data.tags||!Array.isArray(x.data.history)||!Array.isArray(x.data.trashIds)||!Array.isArray(x.data.allTags))throw Error();for(const tags of Object.values(x.data.tags))if(!Array.isArray(tags)||tags.some(t=>typeof t!=='string'))throw Error();if(qs.get('scenario')==='storage-failure')throw Error();localStorage.setItem(PRODUCT_STORE,JSON.stringify(x.data));location.href='app.html?variant='+this.variant+'&state=settings'}catch{this.error='无法恢复：请选择本原型导出的有效备份文件。'}},
 fmt(n){return Math.floor(n/60)+':'+String(Math.floor(n%60)).padStart(2,'0')},
 key(e){if(/INPUT|TEXTAREA|SELECT/.test(e.target.tagName))return;if(e.key==='Escape'){if(this.panel)this.panel='';else if(this.screen==='reader')this.closeReader();else if(this.screen==='video')this.closeVideo();return}if(this.panel)return;if(this.screen==='reader'&&this.mode==='horizontal'){if(e.key==='ArrowRight'){e.preventDefault();this.advance(this.direction==='rtl'?-1:1)}if(e.key==='ArrowLeft'){e.preventDefault();this.advance(this.direction==='rtl'?1:-1)}}}
}));
