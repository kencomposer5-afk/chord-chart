const CACHE='chordchart-v15';
const FILES=['./','./index.html','./manifest.json','./icon-192.png','./icon-512.png',
  './vendor/html2canvas.min.js','./vendor/jspdf.umd.min.js','./vendor/noto-music.woff2','./vendor/pdf.min.js','./vendor/pdf.worker.min.js'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting()));});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET') return;
  e.respondWith(fetch(e.request).then(r=>{const cp=r.clone();caches.open(CACHE).then(c=>c.put(e.request,cp));return r;})
    .catch(()=>caches.match(e.request).then(m=>m||caches.match('./index.html'))));
});
