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
