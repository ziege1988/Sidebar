// SVG-Nachbau von CatPainter (gleiche Koordinaten wie in Cat.swift)
const FUR='#17171a',FURL='#29292e',EAR='#db8c9e',NOSE='#f29eb3',BLUSH='#fa9eb3',IRIS='#edd65c',IRISA='#eda838';
const E=(cx,cy,rx,ry,f,o=1)=>`<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="${f}" opacity="${o}"/>`;
function ear(left,angle){const s=left?1:-1,bx=left?32:68,by=38;
 return `<g transform="rotate(${angle} ${bx} ${by})"><path d="M${50-s*27},46 Q${50-s*30},20 ${50-s*23},14 Q${50-s*15},18 ${50-s*6},32 Z" fill="${FUR}"/><path d="M${50-s*24},40 Q${50-s*26},25 ${50-s*22},21 Q${50-s*16},24 ${50-s*11},33 Z" fill="${EAR}" opacity=".75"/></g>`}
function heart(x,y,s,o){return `<path opacity="${o}" fill="#e6544d" d="M${x},${y+s*.35} C${x-s*.15},${y+s*.1} ${x-s*.5},${y+s*.15} ${x-s*.5},${y-s*.15} A${s*.25},${s*.25} 0 0 1 ${x},${y-s*.15} A${s*.25},${s*.25} 0 0 1 ${x+s*.5},${y-s*.15} C${x+s*.5},${y+s*.15} ${x+s*.15},${y+s*.1} ${x},${y+s*.35} Z"/>`}
function rudi(pose,size,dark,accent){
 const id='r'+Math.random().toString(36).slice(2,7);
 let s=`<svg width="${size}" height="${size}" viewBox="0 0 100 100"><defs><radialGradient id="${id}" cx="50" cy="38" r="70" gradientUnits="userSpaceOnUse"><stop offset="0.05" stop-color="${dark?'#4f544f':'#f7f5eb'}"/><stop offset="1" stop-color="${dark?'#2b2e30':accent}" stop-opacity="${dark?1:.45}"/></radialGradient><clipPath id="${id}c"><circle cx="50" cy="50" r="50"/></clipPath></defs>
 <circle cx="50" cy="50" r="50" fill="${dark?'#2b2e30':'#f7f5eb'}"/><circle cx="50" cy="50" r="50" fill="url(#${id})"/><g clip-path="url(#${id}c)">`;
 if(pose==='sleep'){
  s+=E(52,82,34,5,'#000',dark?.35:.12)+E(56,66,30,16,FUR)+E(60,60,18,6,FURL)+
   `<path d="M84,70 C92,84 62,86 40,80" stroke="${FUR}" stroke-width="7" fill="none" stroke-linecap="round"/>`+E(30,75,7,4,FUR)+
   `<path d="M20,52 Q15,40 21,35 Q28,38 32,45 Z" fill="${FUR}"/><path d="M38,44 Q42,36 48,36 Q51,44 47,52 Z" fill="${FUR}"/>`+
   E(24,43,2.5,3.5,EAR,.7)+E(45,42,2.5,3.5,EAR,.7)+E(34,59,16,14,FUR)+
   `<path d="M26,59 Q29,61.8 32,59 M37,59 Q40,61.8 43,59" stroke="#8c9485" stroke-width="1.4" fill="none" stroke-linecap="round"/>`+
   E(34.5,64,1.6,1.1,NOSE)+E(25,64,3,1.6,BLUSH,.35)+E(44,64,3,1.6,BLUSH,.35)+
   `<g font-family="-apple-system,Arial Rounded MT Bold,sans-serif" font-weight="900" fill="#5c7a57"><text x="64" y="40" font-size="8" opacity=".45">Z</text><text x="70" y="31" font-size="10" opacity=".7">Z</text><text x="77" y="21" font-size="12.5">Z</text></g>`;
 } else {
  const angry=pose==='angry';
  s+=`<path d="M12,104 C14,80 30,70 50,70 C70,70 86,80 88,104 Z" fill="${FUR}"/>`+ear(true,angry?-28:0)+ear(false,angry?28:0)+E(50,52,30,26,FUR)+E(50,41,17,7,FURL);
  if(pose==='purr'){s+=`<path d="M32,55 Q39,48 46,55 M54,55 Q61,48 68,55" stroke="${IRIS}" stroke-width="2.4" fill="none" stroke-linecap="round"/>`}
  else{[[39,1],[61,-1]].forEach(([x,inner])=>{const pw=angry?1.8:(pose==='ask'?5.5:4.2);
    s+=E(x,53,8.5,9,angry?IRISA:IRIS)+E(x,53.5,pw,angry?6.5:7,'#000')+E(x+2.6,49.5,2.3,2.3,'#fff',.95)+E(x-2.6,57,1.1,1.1,'#fff',.8);
    if(pose!=='ask'){const d=angry?7.5:3.2,sl=angry?5:2;s+=`<polygon points="${x-10},43 ${x+10},43 ${x+10},${44+d+(inner<0?sl:0)} ${x-10},${44+d+(inner>0?sl:0)}" fill="${FUR}"/>`}})}
  s+=E(30,63,4.5,2.6,BLUSH,angry?.15:.38)+E(70,63,4.5,2.6,BLUSH,angry?.15:.38)+
   `<path d="M47.6,60.5 Q50,59.3 52.4,60.5 Q51.5,62.2 50,63 Q48.5,62.2 47.6,60.5 Z" fill="${NOSE}"/>`;
  s+=angry?`<path d="M44.5,68 Q50,63.5 55.5,68" stroke="#808080" stroke-width="1.4" fill="none" stroke-linecap="round"/><polygon points="47.5,66.1 48.4,68.6 49.3,65.6" fill="#fff" opacity=".9"/>`
   :`<path d="M45.5,64 Q47.75,66.8 50,64 Q52.25,66.8 54.5,64" stroke="#7a7a7a" stroke-width="1.2" fill="none" stroke-linecap="round"/>`;
  s+=`<g stroke="#999" stroke-width=".7" opacity=".75"><line x1="28" y1="61" x2="12" y2="58"/><line x1="28" y1="63.5" x2="12" y2="64.5"/><line x1="72" y1="61" x2="88" y2="58"/><line x1="72" y1="63.5" x2="88" y2="64.5"/></g>`;
  if(pose==='ask')s+=`<g transform="rotate(4 74 96)">${E(74,88,7,12,FUR)+E(74,79,8.5,7,FUR)+E(74,80.5,2.6,2.2,EAR)+E(69.8,76.8,1.3,1.3,EAR)+E(72.8,74.6,1.3,1.3,EAR)+E(76.2,74.6,1.3,1.3,EAR)+E(79,76.8,1.3,1.3,EAR)}</g>`;
  if(pose==='purr')s+=heart(80,28,8,.9)+heart(18,20,7,.55);
  if(angry)s+=`<path d="M14,20 L20,25 M21,14 L23,21 M10,28 L17,30" stroke="#e6544d" stroke-width="2" stroke-linecap="round"/>`;
 }
 return s+`</g><circle cx="50" cy="50" r="49" fill="none" stroke="rgba(255,255,255,${dark?.35:.8})" stroke-width="2"/><circle cx="50" cy="50" r="47.5" fill="none" stroke="rgba(0,0,0,.12)" stroke-width="1"/></svg>`;
}
// gezackte Blase wie SpikyBubble in Cat.swift
function bubble(ew,eh,tail,style,margin){const sp={normal:[20,.09],angry:[15,.22],purr:[26,.035]}[style];
 const cx=margin+ew/2,cy=margin+eh/2,rx=ew/2,ry=eh/2,ta=Math.atan2(tail[1]-cy,tail[0]-cx),n=sp[0]*2;let pts=[],added=false;
 for(let i=0;i<n;i++){const a=i/n*2*Math.PI,d=Math.atan2(Math.sin(a-ta),Math.cos(a-ta));if(Math.abs(d)<.26){if(!added){pts.push(tail);added=true}continue}
  const k=i%2==0?1:1-sp[1];pts.push([cx+Math.cos(a)*rx*k,cy+Math.sin(a)*ry*k])}
 return pts.map(p=>p.join(',')).join(' ')}

function bustInner(pose){let s='';
  const angry=pose==='angry';
  s+=`<path d="M12,104 C14,80 30,70 50,70 C70,70 86,80 88,104 Z" fill="${FUR}"/>`+ear(true,angry?-28:0)+ear(false,angry?28:0)+E(50,52,30,26,FUR)+E(50,41,17,7,FURL);
  if(pose==='purr'){s+=`<path d="M32,55 Q39,48 46,55 M54,55 Q61,48 68,55" stroke="${IRIS}" stroke-width="2.4" fill="none" stroke-linecap="round"/>`}
  else{[[39,1],[61,-1]].forEach(([x,inner])=>{const pw=angry?1.8:(pose==='ask'?5.5:4.2);
    s+=E(x,53,8.5,9,angry?IRISA:IRIS)+E(x,53.5,pw,angry?6.5:7,'#000')+E(x+2.6,49.5,2.3,2.3,'#fff',.95)+E(x-2.6,57,1.1,1.1,'#fff',.8);
    if(pose!=='ask'){const d=angry?7.5:3.2,sl=angry?5:2;s+=`<polygon points="${x-10},43 ${x+10},43 ${x+10},${44+d+(inner<0?sl:0)} ${x-10},${44+d+(inner>0?sl:0)}" fill="${FUR}"/>`}})}
  s+=E(30,63,4.5,2.6,BLUSH,angry?.15:.38)+E(70,63,4.5,2.6,BLUSH,angry?.15:.38)+
   `<path d="M47.6,60.5 Q50,59.3 52.4,60.5 Q51.5,62.2 50,63 Q48.5,62.2 47.6,60.5 Z" fill="${NOSE}"/>`;
  s+=angry?`<path d="M44.5,68 Q50,63.5 55.5,68" stroke="#808080" stroke-width="1.4" fill="none" stroke-linecap="round"/><polygon points="47.5,66.1 48.4,68.6 49.3,65.6" fill="#fff" opacity=".9"/>`
   :`<path d="M45.5,64 Q47.75,66.8 50,64 Q52.25,66.8 54.5,64" stroke="#7a7a7a" stroke-width="1.2" fill="none" stroke-linecap="round"/>`;
  s+=`<g stroke="#999" stroke-width=".7" opacity=".75"><line x1="28" y1="61" x2="12" y2="58"/><line x1="28" y1="63.5" x2="12" y2="64.5"/><line x1="72" y1="61" x2="88" y2="58"/><line x1="72" y1="63.5" x2="88" y2="64.5"/></g>`;
  if(pose==='ask')s+=`<g transform="rotate(4 74 96)">${E(74,88,7,12,FUR)+E(74,79,8.5,7,FUR)+E(74,80.5,2.6,2.2,EAR)+E(69.8,76.8,1.3,1.3,EAR)+E(72.8,74.6,1.3,1.3,EAR)+E(76.2,74.6,1.3,1.3,EAR)+E(79,76.8,1.3,1.3,EAR)}</g>`;
  if(pose==='purr')s+=heart(80,28,8,.9)+heart(18,20,7,.55);
  if(angry)s+=`<path d="M14,20 L20,25 M21,14 L23,21 M10,28 L17,30" stroke="#e6544d" stroke-width="2" stroke-linecap="round"/>`;

 return s}
