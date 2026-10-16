window.paperViewer = () => ({
  clips: [
    {id:'portrait',name:'花间微风_02.mp4',orientation:'9:16',src:'assets/flower-portrait.mp4',poster:'assets/flower-portrait.jpg',tags:['自然','花卉']},
    {id:'landscape',name:'花间微风_01.mp4',orientation:'16:9',src:'assets/flower-landscape.mp4',poster:'assets/flower-landscape.jpg',tags:['自然','花卉']},
    {id:'macro',name:'花间微风_03.mp4',orientation:'9:16',src:'assets/flower-portrait.mp4',poster:'assets/flower-portrait.jpg',tags:['自然','微距']}
  ],
  filters: [], index: 0, menu: false, panel: '', paused: true, time: 0,
  duration: 5, speed: 1, mediaError: false, draftTags: [], draftFilters: [], deleted: null,
  pointer: null, justSwiped: false, lastWheel: 0, loadVersion: 0,
  allTags: ['自然','花卉','微距','庭院'],
  get results() { return this.clips.filter(c => this.filters.every(t => c.tags.includes(t))); },
  get current() { return this.results[this.index] || null; },
  get visibleTags() { return [...new Set([...(this.current?.tags || []),...this.filters])]; },
  init() {
    const state = new URLSearchParams(location.search).get('state');
    if (state === 'filtered') this.filters = ['花卉'];
    if (state === 'menu') this.menu = true;
    this.$nextTick(() => this.loadClip(false));
  },
  format(value) { const seconds=Math.floor(Number.isFinite(value) ? value : 0); return String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0'); },
  loadClip(play = false) {
    const video=document.querySelector('.viewer video');
    this.loadVersion++;
    const version=this.loadVersion;
    video.pause(); this.time=0; this.mediaError=false; this.paused=true;
    if (!this.current) { video.removeAttribute('src'); video.load(); return; }
    video.src=this.current.src; video.playbackRate=this.speed; video.load();
    if (play) video.play().catch(() => { if (version===this.loadVersion) this.paused=true; });
  },
  tap() {
    if (this.justSwiped) { this.justSwiped=false; return; }
    const video=document.querySelector('.viewer video');
    if (video.paused) video.play().catch(() => { this.mediaError=true; }); else video.pause();
  },
  step(direction) {
    if (this.menu || this.panel || !this.results.length) return;
    const next=this.index+direction;
    if (next<0 || next>=this.results.length) return;
    this.index=next; this.$nextTick(() => this.loadClip(true));
  },
  pointerStart(event) {
    if (this.menu || this.panel || event.target.closest('.controls,.more,.menu,.error')) return;
    this.pointer={x:event.clientX,y:event.clientY}; this.justSwiped=false;
  },
  pointerEnd(event) {
    if (!this.pointer) return;
    const dy=event.clientY-this.pointer.y, dx=event.clientX-this.pointer.x;
    this.pointer=null;
    if (Math.abs(dy)>55 && Math.abs(dy)>Math.abs(dx)*1.3) { this.justSwiped=true; this.step(dy<0 ? 1 : -1); }
  },
  wheel(event) {
    if (event.target.closest('.menu,.sheet,.controls') || Math.abs(event.deltaY)<25 || Date.now()-this.lastWheel<650) return;
    this.lastWheel=Date.now(); this.step(event.deltaY>0 ? 1 : -1);
  },
  toggleFilter(tag) {
    this.setFilters(this.filters.includes(tag) ? this.filters.filter(t=>t!==tag) : [...this.filters,tag]);
  },
  setFilters(tags) {
    const currentId=this.current?.id;
    this.filters=[...tags];
    const match=this.results.findIndex(c=>c.id===currentId);
    this.index=Math.max(0,match);
    if (this.current?.id!==currentId) this.$nextTick(() => this.loadClip(false));
  },
  openFilters() { this.menu=false;this.draftFilters=[...this.filters];this.panel='filters';this.$nextTick(() => document.querySelector('.sheet .close').focus()); },
  editTags() { this.menu=false; this.draftTags=[...(this.current?.tags || [])]; this.panel='tags'; this.$nextTick(() => document.querySelector('.sheet .close').focus()); },
  saveTags() {
    if (this.current) this.current.tags=[...this.draftTags];
    this.panel=''; this.index=Math.min(this.index,Math.max(0,this.results.length-1));
    this.$nextTick(() => this.loadClip(false));
  },
  removeClip() {
    if (!this.current) return;
    const clip=this.current;
    this.deleted={clip,position:this.clips.findIndex(c=>c.id===clip.id)};
    this.clips=this.clips.filter(c=>c.id!==clip.id); this.menu=false;
    this.index=Math.min(this.index,Math.max(0,this.results.length-1));
    this.$nextTick(() => this.loadClip(false));
  },
  undo() {
    if (!this.deleted) return;
    const {clip,position}=this.deleted;
    this.clips.splice(position,0,clip); this.deleted=null;
    const match=this.results.findIndex(c=>c.id===clip.id); this.index=Math.max(0,match);
    this.$nextTick(() => this.loadClip(false));
  },
  trapFocus(event) {
    const buttons=[...event.currentTarget.querySelectorAll('button')].filter(b=>b.getClientRects().length);
    if (!buttons.length) return;
    const first=buttons[0],last=buttons[buttons.length-1];
    if (event.shiftKey && document.activeElement===first) { event.preventDefault();last.focus(); }
    else if (!event.shiftKey && document.activeElement===last) { event.preventDefault();first.focus(); }
  },
  closePanels() { this.menu=false;this.panel='';this.$nextTick(() => document.querySelector('.more')?.focus()); }
});
