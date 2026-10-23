window.PACKS = [
  {
    "id": "summer",
    "title": "夏日祭",
    "author": "示例作者",
    "number": "034",
    "folder": "示例作者 NO.034 - 夏日祭",
    "sourceCount": 67,
    "pages": [
      "assets/pages/summer-1.svg",
      "assets/pages/summer-2.svg",
      "assets/pages/summer-3.svg",
      "assets/pages/summer-4.svg",
      "assets/pages/summer-5.svg",
      "assets/pages/summer-6.svg"
    ],
    "tags": [
      "和服",
      "户外"
    ],
    "sizes": [
      [
        4000,
        6000
      ],
      [
        4016,
        6016
      ],
      [
        6000,
        4000
      ],
      [
        3984,
        5968
      ],
      [
        4016,
        6016
      ],
      [
        4000,
        6000
      ]
    ]
  },
  {
    "id": "field",
    "title": "原野上的浪漫",
    "author": "示例作者",
    "number": "057",
    "folder": "示例作者 NO.057 - 原野上的浪漫",
    "sourceCount": 51,
    "pages": [
      "assets/pages/field-1.svg",
      "assets/pages/field-2.svg",
      "assets/pages/field-3.svg",
      "assets/pages/field-4.svg",
      "assets/pages/field-5.svg",
      "assets/pages/field-6.svg"
    ],
    "tags": [
      "户外",
      "白裙"
    ],
    "sizes": [
      [
        8334,
        5559
      ],
      [
        7952,
        5304
      ],
      [
        7952,
        5304
      ],
      [
        5304,
        7952
      ],
      [
        5304,
        7952
      ],
      [
        7952,
        5304
      ]
    ]
  },
  {
    "id": "newyear",
    "title": "灵梦 · 新年快乐",
    "author": "示例作者",
    "number": "019",
    "folder": "示例作者 NO.019 - 灵梦 · 新年快乐",
    "sourceCount": 45,
    "pages": [
      "assets/pages/newyear-1.svg",
      "assets/pages/newyear-2.svg",
      "assets/pages/newyear-3.svg",
      "assets/pages/newyear-4.svg",
      "assets/pages/newyear-5.svg",
      "assets/pages/newyear-6.svg"
    ],
    "tags": [
      "角色",
      "和服"
    ],
    "sizes": [
      [
        4000,
        6000
      ],
      [
        4000,
        6000
      ],
      [
        6000,
        3375
      ],
      [
        4000,
        6000
      ],
      [
        6000,
        4000
      ],
      [
        6000,
        4000
      ]
    ]
  },
  {
    "id": "kimono",
    "title": "加藤惠 · 和服",
    "author": "示例作者",
    "number": "051",
    "folder": "示例作者 NO.051 - 加藤惠 · 和服",
    "sourceCount": 23,
    "pages": [
      "assets/pages/kimono-1.svg",
      "assets/pages/kimono-2.svg",
      "assets/pages/kimono-3.svg",
      "assets/pages/kimono-4.svg",
      "assets/pages/kimono-5.svg",
      "assets/pages/kimono-6.svg"
    ],
    "tags": [
      "角色",
      "和服"
    ],
    "sizes": [
      [
        5304,
        7952
      ],
      [
        7952,
        5304
      ],
      [
        5304,
        7952
      ],
      [
        5304,
        7952
      ],
      [
        5304,
        7952
      ],
      [
        7952,
        5304
      ]
    ]
  }
];

;
const qs = new URLSearchParams(location.search);
const VARIANT = qs.get('variant') || 'b';
const STORE = 'video-viewer-image-packs-prototype-v1-' + VARIANT;
const icons = {
 back:'<path d="m14 5-7 7 7 7"/>', next:'<path d="m9 5 7 7-7 7"/>',
 folder:'<path d="M3 7V5h6l2 2h10v12H3Z"/>', more:'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
 grid:'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
 book:'<path d="M3 4h6c2 0 3 1 3 2 0-1 1-2 3-2h6v16h-6c-2 0-3 1-3 1s-1-1-3-1H3Z M12 6v15"/>',
 tag:'<path d="m3 3 9 0 9 9-9 9-9-9Z"/><circle cx="8" cy="8" r="1.5"/>',
 settings:'<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3" fill="currentColor"/><circle cx="16" cy="17" r="3" fill="currentColor"/>',
 search:'<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>', close:'<path d="m6 6 12 12M6 18 18 6"/>',
 shuffle:'<path d="m3 6 3 0 12 12h3m-4-4 4 4-4 4M3 18h3L18 6h3m-4-4 4 4-4 4"/>',
 check:'<path d="m5 12 5 5L20 7"/>', play:'<rect x="3" y="3" width="18" height="18" rx="3"/><path d="m10 8 6 4-6 4Z"/>',
 down:'<path d="m6 9 6 6 6-6"/>', expand:'<path d="M8 3H3v5m13-5h5v5M3 16v5h5m8 0h5v-5"/>',
 filter:'<path d="M3 6h18M6 12h12M9 18h6"/>', history:'<path d="M4 5v5h5M4 10a8 8 0 1 1 1 8M12 7v6l4 2"/>',
 horizontal:'<rect x="5" y="3" width="14" height="18" rx="1"/><path d="M1 12h5m12 0h5"/>',
 vertical:'<rect x="5" y="2" width="14" height="8" rx="1"/><rect x="5" y="14" width="14" height="8" rx="1"/>',
 up:'<path d="m6 15 6-6 6 6"/>'
};
window.packApp = () => ({
 variant:VARIANT, screen:'home', tab:VARIANT==='b'?'library':'browse', panel:'', controls:true,
 packs:JSON.parse(JSON.stringify(PACKS)), selected:0, page:0, mode:'horizontal', direction:'ltr', fit:'contain', gap:false,
 progress:{summer:2}, preferences:{}, last:'summer', search:'', searchOpen:false, filter:'', statusFilter:'全部', sort:'名称',
 multi:false, chosen:[], draftTags:[], tagInput:'', notice:'', error:'', failedImage:false, zoom:false,
 returnScreen:'home', returnTab:'library', savedScroll:0, gesture:null, allTags:['和服','户外','白裙','角色','喜欢'],
 get pack(){return this.packs[this.selected]},
 get pageCount(){return this.pack.pages.length},
 get filtered(){return this.packs.filter(p=>(!this.filter||p.tags.includes(this.filter))&&(!this.search||(`${p.title} ${p.author} ${p.folder}`).includes(this.search))&&(this.statusFilter!=='未读'||this.progress[p.id]===undefined)&&(this.statusFilter!=='在读'||(this.progress[p.id]!==undefined&&this.progress[p.id]<p.pages.length-1))).sort((a,b)=>this.sort==='名称'?a.number.localeCompare(b.number):this.packs.indexOf(a)-this.packs.indexOf(b))},
 get recent(){return this.packs.find(p=>p.id===this.last)||this.packs[0]},
 get tagTargets(){return this.chosen.length?this.packs.filter(p=>this.chosen.includes(p.id)):[this.pack]},
 icon(name){return '<svg aria-hidden="true" viewBox="0 0 24 24">'+(icons[name]||icons.more)+'</svg>'},
 init(){
   if(qs.has('reset'))localStorage.removeItem(STORE);
   try {const d=JSON.parse(localStorage.getItem(STORE)||'null');if(d){this.progress=d.progress||{};this.last=d.last||'summer';this.preferences=d.preferences||{};this.packs.forEach(p=>{if(d.tags?.[p.id])p.tags=d.tags[p.id]});this.allTags=[...new Set([...this.allTags,...this.packs.flatMap(p=>p.tags)])]}}
   catch{this.error='阅读记录暂时无法读取，仍可浏览图包。'}
   if(VARIANT==='c'||qs.get('state')==='reader'||qs.get('state')==='vertical') this.openPack(this.recent.id);
   if(VARIANT==='c'&&!this.preferences[this.pack.id])this.changeMode('vertical');
   if(qs.get('state')==='vertical')this.changeMode('vertical');
   if(qs.get('state')==='settings'){this.openPack('summer');this.panel='reader-settings'}
   if(qs.get('state')==='tags'){this.openPack('summer');this.editTags()}
   this.$watch('panel',v=>{if(v)this.$nextTick(()=>this.$refs.sheet?.focus())});
 },
 save(){
   try{if(qs.get('scenario')==='storage-failure')throw Error('storage');localStorage.setItem(STORE,JSON.stringify({progress:this.progress,last:this.last,preferences:this.preferences,tags:Object.fromEntries(this.packs.map(p=>[p.id,p.tags]))}));return true}
   catch{this.error='保存失败，阅读记录和标签未写入。请重试。';return false}
 },
 toast(s){this.notice=s;clearTimeout(this._toast);this._toast=setTimeout(()=>this.notice='',3500)},
 goTab(t){this.tab=t;this.screen='home';this.panel='';this.multi=false;this.chosen=[];this.$nextTick(()=>{if(this.$refs.library)this.$refs.library.scrollTop=this.savedScroll})},
 openPack(id){
   const n=this.packs.findIndex(p=>p.id===id);if(n<0)return;
   if(this.screen!=='reader'){this.returnScreen=this.screen;this.returnTab=this.tab;this.savedScroll=this.$refs.library?.scrollTop||0}
   this.selected=n;this.page=this.progress[id]??0;this.mode=this.preferences[id]?.mode||'horizontal';this.direction=this.preferences[id]?.direction||'ltr';this.gap=this.preferences[id]?.gap||false;
   this.last=id;this.screen='reader';this.panel='';this.controls=true;this.zoom=false;this.failedImage=false;this.save();this.$nextTick(()=>this.scrollToPage());
 },
 closeReader(){this.zoom=false;this.screen='home';this.panel='';this.tab=VARIANT==='c'?'library':this.returnTab;this.$nextTick(()=>{if(this.$refs.library)this.$refs.library.scrollTop=this.savedScroll})},
 record(){this.progress[this.pack.id]=this.page;this.last=this.pack.id;this.failedImage=false;this.save()},
 jump(n){this.page=Math.max(0,Math.min(this.pageCount-1,Number(n)));this.zoom=false;this.record();this.$nextTick(()=>this.scrollToPage())},
 advance(delta){if(this.page+delta>=this.pageCount){this.panel='finished';return}this.jump(this.page+delta)},
 randomPack(){const options=this.packs.map((p,i)=>i).filter(i=>i!==this.selected);this.selected=options[Math.floor(Math.random()*options.length)];this.toast('已随机选中 '+this.pack.title)},
 movePack(delta,read=false){this.selected=(this.selected+delta+this.packs.length)%this.packs.length;if(read)this.openPack(this.pack.id)},
 scrollToPage(){if(this.mode==='vertical'&&this.$refs.strip){const e=this.$refs.strip.querySelector(`[data-page="${this.page}"]`);if(e)this.$refs.strip.scrollTop=e.offsetTop}},
 onScroll(){
   if(this.mode!=='vertical'||this.screen!=='reader')return;
   const root=this.$refs.strip, y=root.getBoundingClientRect().top+root.clientHeight*.35;
   const images=[...root.querySelectorAll('[data-page]')];const e=images.find(e=>e.getBoundingClientRect().bottom>y);
   if(e&&+e.dataset.page!==this.page){this.page=+e.dataset.page;clearTimeout(this._save);this._save=setTimeout(()=>this.record(),180)}
 },
 changeMode(m){this.mode=m;this.zoom=false;this.preferences[this.pack.id]={mode:m,direction:this.direction,gap:this.gap};this.save();this.$nextTick(()=>this.scrollToPage())},
 editTags(){this.draftTags=this.chosen.length?[]:[...this.tagTargets[0].tags];this.tagInput='';this.panel='tags'},
 toggleTag(t){this.draftTags=this.draftTags.includes(t)?this.draftTags.filter(x=>x!==t):[...this.draftTags,t]},
 addTag(){const t=this.tagInput.trim();if(t&&!this.draftTags.includes(t)){this.draftTags.push(t);if(!this.allTags.includes(t))this.allTags.push(t)}this.tagInput=''},
 saveTags(){this.addTag();const old=this.tagTargets.map(p=>[p.id,[...p.tags]]);this.tagTargets.forEach(p=>{p.tags=this.chosen.length?[...new Set([...p.tags,...this.draftTags])]:[...this.draftTags]});if(!this.save()){old.forEach(([id,t])=>this.packs.find(p=>p.id===id).tags=t);return}const count=this.tagTargets.length;this.panel='';this.toast(`已为 ${count} 个图包保存标签`)},
 selectPack(id){this.chosen=this.chosen.includes(id)?this.chosen.filter(x=>x!==id):[...this.chosen,id]},
 setFilter(t){this.filter=this.filter===t?'':t;this.multi=false;this.chosen=[]},
 startGesture(e){this.gesture={x:e.clientX,y:e.clientY,time:Date.now()}},
 endGesture(e,cover=false){if(!this.gesture)return;const dx=e.clientX-this.gesture.x,dy=e.clientY-this.gesture.y;this.gesture=null;
   if(cover){if(Math.abs(dy)>50){this.movePack(dy<0?1:-1);return}if(Math.abs(dx)<8&&Math.abs(dy)<8)this.openPack(this.pack.id);return}
   if(this.zoom||this.mode==='vertical')return;
   if(Math.abs(dx)>45&&Math.abs(dx)>Math.abs(dy)){this.advance((dx<0?1:-1)*(this.direction==='rtl'?-1:1));return}
   if(Math.abs(dx)<8&&Math.abs(dy)<8){const r=e.currentTarget.getBoundingClientRect(),x=(e.clientX-r.left)/r.width;if(x<.22)this.advance(this.direction==='rtl'?1:-1);else if(x>.78)this.advance(this.direction==='rtl'?-1:1);else this.controls=!this.controls}
 },
 key(e){if(/INPUT|TEXTAREA|SELECT/.test(e.target.tagName))return;if(e.key==='Escape'){if(this.panel)this.panel='';else if(this.screen==='reader')this.closeReader();return}if(this.panel)return;if(this.screen==='reader'&&this.mode==='horizontal'){if(e.key==='ArrowRight'){e.preventDefault();this.advance(this.direction==='rtl'?-1:1)}if(e.key==='ArrowLeft'){e.preventDefault();this.advance(this.direction==='rtl'?1:-1)}}},
});

;
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

;
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

;
/* Prototype settings state: local fixtures only, no NAS requests or filesystem operations. */
const DEVICE_STORE='liubai-device-preferences-v1',ROLLBACK_STORE='liubai-before-restore-v1';
Object.assign(icons,{link:'<path d="m9 15 6-6M8 17l-1 1a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0m0 10a4 4 0 0 0 6 0l5-5a4 4 0 0 0-6-6l-1 1"/>',trash:'<path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',backup:'<path d="M4 3h13l3 3v15H4ZM8 3v6h8V3M8 21v-8h8v8"/>',edit:'<path d="m4 16 12-12 4 4L8 20H4Zm9-9 4 4"/>',moon:'<path d="M20 15A9 9 0 0 1 9 4a9 9 0 1 0 11 11Z"/>'});
const cloneSettings=value=>JSON.parse(JSON.stringify(value));
const baseLibraryApp=window.libraryApp;
window.libraryApp=()=>{
 const app=baseLibraryApp(),prior={init:app.init,snapshot:app.snapshotData,begin:app.beginQueue,openPack:app.openPack,restore:app.restore,title:Object.getOwnPropertyDescriptor(app,'sheetTitle').get,all:Object.getOwnPropertyDescriptor(app,'allItems').get};
 return Object.defineProperties(app,Object.getOwnPropertyDescriptors({
 devicePrefs:{dark:false,preload:true},defaultOrder:'顺序',readerDefaults:{direction:'ltr',gap:false},
 rootDefs:[{id:'video-root',name:'短视频',path:'/media/videos',kind:'video',enabled:true,available:true},{id:'pack-root',name:'217 Cos图包',path:'/media/packs',kind:'pack',enabled:true,available:true}],
 missingRecords:[],jobs:[],permanentIds:[],trashChosen:[],rootDraft:{},restoreMappings:{},restoreConfirmed:false,purgeConfirmed:false,rollbackAvailable:false,
 connectionForm:{address:'',port:'',passphrase:''},connecting:false,connectionStatus:'',tagSearchByKind:{video:'',pack:''},videoFull:false,scanning:false,scanProgress:0,scanStatus:'',taskBusy:false,
 get visibleCatalog(){const q=this.tagSearchByKind[this.kind].trim().toLowerCase();return this.currentCatalog.filter(t=>t.toLowerCase().includes(q))},
 async toggleVideoFull(){try{if(document.fullscreenElement){await document.exitFullscreen();this.videoFull=false}else{await document.querySelector('.video-stage').requestFullscreen();this.videoFull=true}}catch{this.error='浏览器未能进入全屏，请重试。'}},
 get allItems(){return prior.all.call(this).filter(i=>!this.permanentIds.includes(i.id))},
 get pendingJobs(){return this.jobs.filter(j=>j.status==='pending'||j.status==='running').length},
 get managementPanel(){return ['connection','roots','missing','trash','backup','tasks'].includes(this.panel)},
 get sheetTitle(){return ({rootForm:this.rootDraft.id?'编辑媒体目录':'添加媒体目录',missing:'缺失内容',clearMissing:'清除失效记录',playback:'播放顺序',videoDetails:'视频详情',purge:'永久删除',tasks:'操作任务'})[this.panel]||prior.title.call(this)},
 get backupSummary(){const d=this.pendingImport;if(!d)return '';return '视频标签 '+d.tagCatalog.video.length+' · 图包标签 '+d.tagCatalog.pack.length+' · 目录 '+(d.rootDefs?.length||0)+' · 回收站 '+d.trashIds.length},
 init(){prior.init.call(this);try{const d=qs.has('snapshot')?null:JSON.parse(localStorage.getItem(LIBRARY_STORE)||'null');for(const k of ['rootDefs','missingRecords','jobs','permanentIds','defaultOrder','readerDefaults'])if(d?.[k]!==undefined)this[k]=d[k];if(d&&!d.rootDefs)this.rootDefs=this.rootDefs.map(r=>({...r,enabled:d.rootEnabled?.[r.kind]??true}));if(!qs.has('snapshot'))this.devicePrefs={...this.devicePrefs,...JSON.parse(localStorage.getItem(DEVICE_STORE)||'{}')};this.rollbackAvailable=!!localStorage.getItem(ROLLBACK_STORE);this.jobs=this.jobs.map(j=>j.status==='running'?{...j,status:'pending'}:j);if(d?.previewRound&&this.screen==='home'){this.queueIds=d.previewRound.ids.filter(id=>this.allItems.some(i=>i.id===id)&&!this.trashIds.includes(id));this.queueOriginal=[...this.queueIds];this.queueAt=Math.max(0,Math.min(d.previewRound.at||0,this.queueIds.length-1));this.queueLabel=d.previewRound.label||'';this.queueOrder=d.previewRound.order||'顺序'}}catch{this.error='设置记录读取失败，当前仍可浏览。'}
 document.addEventListener('fullscreenchange',()=>{this.videoFull=!!document.fullscreenElement});this.syncRootTypes();const state=qs.get('state');if(['connection','roots','missing','trash','backup','tasks','playback','dark'].includes(state)){this.tab='settings';this.screen='home';if(state==='dark')this.devicePrefs.dark=true;else this.openSettings(state)}
 if(state==='missing')this.missingRecords=[{id:'missing-v',title:'林间片段.mp4',path:'/media/videos/林间片段.mp4',kind:'video',tags:['户外'],offline:false},{id:'offline-pack',title:'春日图包',path:'/media/archive/春日图包',kind:'pack',tags:['户外'],offline:true}];
 if(state==='restore-preview'){this.tab='settings';this.prepareImport({schema:'library-first-v3',data:this.snapshotData()})}if(state==='purge'){this.tab='settings';this.trashIds=['summer'];this.trashKind='pack';this.trashChosen=['summer'];this.panel='purge'}
 if(state==='tasks'&&!this.jobs.length)this.jobs=[{id:'scan-example',title:'同步外部变更',kind:'scan',status:'pending',created:new Date().toISOString()}];
 if(state==='trash'&&!this.trashIds.length)this.trashIds=['v-portrait','summer'];
 },
 snapshotData(){return {...prior.snapshot.call(this),rootDefs:this.rootDefs,missingRecords:this.missingRecords,jobs:this.jobs,permanentIds:this.permanentIds,defaultOrder:this.defaultOrder,readerDefaults:this.readerDefaults,previewRound:{ids:this.queueIds,at:this.queueAt,label:this.queueLabel,order:this.queueOrder}}},
 commitSettings(changes){const old={};for(const k in changes){old[k]=cloneSettings(this[k]);this[k]=changes[k]}if(this.save())return true;for(const k in old)this[k]=old[k];return false},
 setDevicePreference(key,value){const next={...this.devicePrefs,[key]:value};try{if(qs.get('scenario')==='storage-failure')throw Error();if(!qs.has('snapshot'))localStorage.setItem(DEVICE_STORE,JSON.stringify(next));this.devicePrefs=next}catch{this.error='偏好保存失败，原设置保留。';this.$nextTick(()=>document.querySelectorAll('[role="switch"]').forEach(e=>e.checked=e.getAttribute('aria-label')==='暗黑模式'?this.devicePrefs.dark:this.devicePrefs.preload))}},
 setDefaultOrder(value){this.commitSettings({defaultOrder:value})},
 setReaderDefault(key,value){this.commitSettings({readerDefaults:{...this.readerDefaults,[key]:value}})},
 beginQueue(items,label,id){prior.begin.call(this,items,label,id);if(items.length&&this.defaultOrder==='随机')this.setQueueOrder('随机')},
 openPack(id){const has=this.preferences[id];prior.openPack.call(this,id);if(!has&&this.screen==='reader'){this.direction=this.readerDefaults.direction;this.gap=this.readerDefaults.gap;this.preferences[id]={mode:this.mode,direction:this.direction,gap:this.gap,fit:this.fit};this.save()}},
 openSettings(name){this.panel=name;this.error='';if(name==='trash')this.trashChosen=[];if(name==='connection'){const u=new URL(this.connection);this.connectionForm={address:u.protocol+'//'+u.hostname,port:u.port||(u.protocol==='https:'?'443':'80'),passphrase:''};this.connectionStatus=''}},
 async saveConnection(){let u;try{u=new URL(this.connectionForm.address);const port=Number(this.connectionForm.port);if(!['http:','https:'].includes(u.protocol)||!Number.isInteger(port)||port<1||port>65535||u.username||u.password)throw Error();u.port=String(port)}catch{this.error='请输入 http(s) 服务地址和 1–65535 之间的端口。';return}
 if(!this.connectionForm.passphrase.trim()){this.error='请输入个人口令。';return}this.error='';this.connecting=true;await new Promise(r=>setTimeout(r,450));this.connecting=false;
 if(qs.get('scenario')==='connection-failure'){this.error='连接失败，请检查地址、端口和个人口令。输入已保留。';return}if(this.commitSettings({connection:u.origin})){this.connectionForm.passphrase='';this.connectionStatus='连接配置已保存';this.panel='';this.toast('连接配置已保存')}
 },
 syncRootTypes(){this.rootEnabled={video:this.rootDefs.some(r=>r.kind==='video'&&r.enabled&&r.available),pack:this.rootDefs.some(r=>r.kind==='pack'&&r.enabled&&r.available)}},
 editRoot(r){this.rootDraft=r?cloneSettings(r):{id:'',name:'',path:'',kind:'pack',enabled:true,available:true};this.panel='rootForm'},
 saveRoot(){const d={...this.rootDraft,name:this.rootDraft.name.trim(),path:this.rootDraft.path.trim().replace(/\/+$/,'')};if(!d.name||!d.path.startsWith('/')){this.error='请输入目录名称和以 / 开头的服务内挂载路径。';return}if(this.rootDefs.some(r=>r.id!==d.id&&r.path===d.path)){this.error='这个挂载路径已添加，请编辑已有目录。';return}if(!d.id)d.id='root-'+Date.now();const list=this.rootDefs.some(r=>r.id===d.id)?this.rootDefs.map(r=>r.id===d.id?d:r):[...this.rootDefs,d];const enabled={video:list.some(r=>r.kind==='video'&&r.enabled&&r.available),pack:list.some(r=>r.kind==='pack'&&r.enabled&&r.available)};if(this.commitSettings({rootDefs:list,rootEnabled:enabled})){this.panel='roots';this.error='';this.toast('媒体目录已保存')}},
 async scanRoots(){if(this.scanning)return;if(this.jobs.some(j=>j.kind==='scan'&&['pending','running'].includes(j.status))){this.panel='tasks';return}const job={id:'job-'+Date.now(),kind:'scan',title:'同步外部变更',status:'running',created:new Date().toISOString()};if(!this.commitSettings({jobs:[...this.jobs,job]}))return;this.scanning=true;this.scanProgress=10;this.scanStatus='检查媒体目录';for(const [progress,label] of [[45,'扫描视频与图包目录'],[80,'核对内容与缺失记录']]){await new Promise(r=>setTimeout(r,400));this.scanProgress=progress;this.scanStatus=label}this.scanning=false;const failed=qs.get('scenario')==='scan-failure';this.scanStatus=failed?'同步未完成，已有内容与记录保留':'同步完成 · '+this.available.length+' 个内容';this.scanProgress=failed?80:100;this.commitSettings({jobs:this.jobs.map(j=>j.id===job.id?{...j,status:failed?'failed':'done'}:j)});},
 clearMissing(){if(this.commitSettings({missingRecords:this.missingRecords.filter(r=>r.offline)})){this.panel='missing';this.toast('已清除失效记录，离线目录记录保留')}},
 toggleTrash(id){this.trashChosen=this.trashChosen.includes(id)?this.trashChosen.filter(x=>x!==id):[...this.trashChosen,id]},
 restore(id){prior.restore.call(this,id);this.trashChosen=this.trashChosen.filter(x=>this.trashIds.includes(x))},
 restoreTrashSelection(){if(this.commitSettings({trashIds:this.trashIds.filter(id=>!this.trashChosen.includes(id))})){this.trashChosen=[];this.toast('已恢复所选内容，标签和进度保留')}},
 async purgeTrash(){if(!this.purgeConfirmed||!this.trashChosen.length||this.taskBusy)return;const job={id:'job-'+Date.now(),kind:'purge',title:'永久删除 '+this.trashChosen.length+' 个'+(this.trashKind==='video'?'视频':'图包'),ids:[...this.trashChosen],status:'pending',created:new Date().toISOString()};if(!this.commitSettings({jobs:[...this.jobs,job]}))return;this.taskBusy=true;await new Promise(r=>setTimeout(r,500));this.taskBusy=false;if(qs.get('scenario')==='operation-pending'){this.panel='tasks';return}if(this.finishJob(job)){this.trashChosen=[];this.panel='trash';this.lastRemoved=null;this.toast('永久删除已完成')}},
 finishJob(job){if(job.kind==='restore'){this.applyRestore(job.data,job.id);return true}const changes={jobs:this.jobs.map(j=>j.id===job.id?{...j,status:'done'}:j)};if(job.kind==='purge'){changes.permanentIds=[...new Set([...this.permanentIds,...job.ids])];changes.trashIds=this.trashIds.filter(id=>!job.ids.includes(id));changes.history=this.history.filter(id=>!job.ids.includes(id))}return this.commitSettings(changes)},
 async queryJob(id){if(this.taskBusy)return;this.taskBusy=true;await new Promise(r=>setTimeout(r,400));this.taskBusy=false;const j=this.jobs.find(j=>j.id===id);if(j)this.finishJob(j)},
 jobLabel(j){return ({pending:'结果待确认 · 可继续浏览',running:'处理中 · 可继续浏览',done:'已完成',failed:'未完成 · 原数据保留'})[j.status]},
 exportData(){if(!this.save())return;const data=this.snapshotData();delete data.connection;delete data.jobs;const text=JSON.stringify({schema:'library-first-v3',createdAt:new Date().toISOString(),data},null,2);const url=URL.createObjectURL(new Blob([text],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='留白-媒体库原型备份.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)},
 prepareImport(x){if(x.schema!=='library-first-v3'||!x.data||!x.data.tags||!Array.isArray(x.data.history)||!Array.isArray(x.data.trashIds)||!['video','pack'].every(k=>Array.isArray(x.data.tagCatalog?.[k])&&x.data.tagCatalog[k].every(t=>typeof t==='string')))throw Error();if(Object.values(x.data.tags).some(a=>!Array.isArray(a)||a.some(t=>typeof t!=='string')))throw Error();if(x.data.rootDefs&&!x.data.rootDefs.every(r=>typeof r.id==='string'&&typeof r.path==='string'&&['video','pack'].includes(r.kind)))throw Error();this.pendingImport=x.data;this.pendingImport.rootDefs??=cloneSettings(this.rootDefs);this.restoreMappings=Object.fromEntries(this.pendingImport.rootDefs.map(r=>[r.id,r.path]));this.restoreConfirmed=false;this.panel='restoreBackup'},
 async importData(e){try{const f=e.target.files[0];if(!f)return;if(f.size>32*1024*1024)throw Error();this.prepareImport(JSON.parse(await f.text()))}catch{this.error='备份格式、版本或内容不正确，现有数据未改变。'}finally{e.target.value=''}},
 loadRollback(){try{this.prepareImport(JSON.parse(localStorage.getItem(ROLLBACK_STORE)))}catch{this.error='恢复前快照无法读取，现有数据未改变。'}},
 confirmRestore(){if(!this.restoreConfirmed)return;for(const value of Object.values(this.restoreMappings))if(value.trim()&&!value.trim().startsWith('/')){this.error='目录映射必须是以 / 开头的路径，或留空暂不启用。';return}
 const d=cloneSettings(this.pendingImport);d.rootDefs=d.rootDefs.map(r=>({...r,path:this.restoreMappings[r.id].trim()||r.path,enabled:!!this.restoreMappings[r.id].trim()&&r.enabled}));
 if(qs.get('scenario')==='operation-pending'){const j={id:'job-'+Date.now(),kind:'restore',title:'恢复管理数据',status:'pending',data:d,created:new Date().toISOString()};if(this.commitSettings({jobs:[...this.jobs,j]}))this.panel='tasks';return}this.applyRestore(d);
 },
 applyRestore(data,jobId){try{if(qs.get('scenario')==='storage-failure')throw Error();const d=cloneSettings(data);d.connection=this.connection;d.permanentIds=[...new Set([...this.permanentIds,...(d.permanentIds||[])])];d.trashIds=d.trashIds.filter(id=>!d.permanentIds.includes(id));d.jobs=jobId?this.jobs.map(j=>j.id===jobId?{id:j.id,title:j.title,kind:j.kind,status:'done',created:j.created}:j):[...this.jobs,{id:'job-'+Date.now(),title:'恢复管理数据',kind:'restore',status:'done',created:new Date().toISOString()}];localStorage.setItem(ROLLBACK_STORE,JSON.stringify({schema:'library-first-v3',data:this.snapshotData()}));localStorage.setItem(LIBRARY_STORE,JSON.stringify(d));location.href='app.html?state=settings'}catch{this.error='恢复失败，现有数据保留。'}}
 }));
};
