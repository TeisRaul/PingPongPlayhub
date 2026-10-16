// Teste pentru plata cu cardul (functions/bookings.js), cu Firestore și Stripe simulate.
const test=require('node:test');
const Module=require('module');const assert=require('assert');const store={};
const clone=o=>JSON.parse(JSON.stringify(o));
function setPath(obj,path,val){const ks=path.split('.');let o=obj;for(let i=0;i<ks.length-1;i++){o[ks[i]]=o[ks[i]]||{};o=o[ks[i]];}o[ks[ks.length-1]]=val;}
function applyUpdate(p,d){if(!store[p])throw new Error('no doc '+p);for(const[k,v]of Object.entries(d)){if(v&&v.__arrayUnion){const cur=store[p][k]||[];store[p][k]=cur.concat(v.__arrayUnion);}else setPath(store[p],k,v);}}
function docRef(p){return{path:p,id:p.split('/').pop(),async get(){return snap(p)},async set(d,o){store[p]=o&&o.merge?{...(store[p]||{}),...d}:d},async update(d){applyUpdate(p,d)},async delete(){delete store[p]},collection(c){return col(p+'/'+c)}}}
function snap(p){return{exists:p in store,id:p.split('/').pop(),data:()=>store[p]&&clone(store[p]),ref:docRef(p)}}
function col(c){const filters=[];const q={where(f,op,v){filters.push([f,v]);return q},async get(){const docs=Object.keys(store).filter(k=>k.startsWith(c+'/')&&k.split('/').length===c.split('/').length+1&&filters.every(([f,v])=>store[k][f]===v)).map(snap);return{docs,empty:!docs.length}},doc:id=>docRef(c+'/'+id),async add(d){const id='n'+Math.random().toString(36).slice(2);store[c+'/'+id]=d;return docRef(c+'/'+id)}};return q}
const db={collection:c=>col(c),async runTransaction(fn){return fn({get:r=>r.get(),update:(r,d)=>applyUpdate(r.path,d)})}};
const admin={firestore:Object.assign(()=>db,{FieldValue:{serverTimestamp:()=>'TS',arrayUnion:(...a)=>({__arrayUnion:a})}}),auth:()=>({})};
const refunds=[];const pis={};
const stripe={refunds:{async create(o,k){refunds.push({pi:o.payment_intent,amount:o.amount,key:k.idempotencyKey,rev:!!o.reverse_transfer})}},paymentIntents:{async retrieve(id){return pis[id]||{id}}}};
const orig=Module._load;Module._load=function(r){if(r==='firebase-admin')return admin;if(r==='firebase-functions/v2/scheduler')return{onSchedule:(o,f)=>f};if(r==='firebase-functions/v2/https')return{onRequest:(o,f)=>f};if(r==='firebase-functions/params')return{defineSecret:()=>({value:()=>'sk'})};if(r==='stripe')return()=>stripe;return orig.apply(this,arguments)};
const b=require('../bookings.js');
const future='2030-01-10', past='2020-01-10';
const notifs=t=>Object.entries(store).filter(([k,v])=>k.startsWith('notifications/')&&v.type===t).map(([,v])=>v);
test('plata cu cardul: împărțire, renunțare, anulare, decontare',async()=>{
 // --- rezervare împărțită la 4: masă 40 RON, gazda plătește 45
 store['matches/s1']={hostUid:'H',hostUsername:'Gazda',locationId:'V',locationName:'sala',date:future,startHour:18,endHour:19,tableId:2,price:40,maxPlayers:4,paymentMode:'split',paymentMethod:'Card în aplicație',paymentStatus:'awaiting_payment',status:'open',joinedUids:['H'],joinedPlayers:[{uid:'H',username:'Gazda'}]};
 assert.strictEqual(await b.confirmPayment(stripe,{id:'pi_H',amount:4500,metadata:{kind:'booking',matchId:'s1',uid:'H'}}),'confirmed');
 let m=store['matches/s1'];
 assert.strictEqual(m.shareAmount,11.25); assert.strictEqual(m.hostReimbursed,false);
 assert.deepStrictEqual(m.cardPayments.H,{pi:'pi_H',amount:45,refunded:0,role:'host'});
 // jucător neînscris nu poate plăti
 await assert.rejects(b.purposeMetadata({kind:'share',matchId:'s1'},'P1','V'),e=>e.status===403);
 // P1, P2 se alătură
 m.joinedUids.push('P1','P2'); m.joinedPlayers.push({uid:'P1',username:'Ana'},{uid:'P2',username:'Bob'});
 const pm=await b.purposeMetadata({kind:'share',matchId:'s1'},'P1','V');
 assert.deepStrictEqual(pm,{meta:{kind:'share',matchId:'s1'},amountRon:11.25});
 await assert.rejects(b.purposeMetadata({kind:'share',matchId:'s1'},'H','V'),e=>e.status===403,'gazda nu plătește parte');
 assert.strictEqual(await b.confirmPayment(stripe,{id:'pi_P1',amount:1125,metadata:{kind:'share',matchId:'s1',uid:'P1'}}),'share_paid');
 assert.strictEqual(await b.confirmPayment(stripe,{id:'pi_P1',amount:1125,metadata:{kind:'share',matchId:'s1',uid:'P1'}}),'already');
 assert.strictEqual(await b.confirmPayment(stripe,{id:'pi_P2',amount:1125,metadata:{kind:'share',matchId:'s1',uid:'P2'}}),'share_paid');
 await assert.rejects(b.purposeMetadata({kind:'share',matchId:'s1'},'P1','V'),e=>e.status===409,'nu plătește de două ori');
 assert.strictEqual(notifs('share_paid').length,2);
 assert.strictEqual(refunds.length,0);
 // P2 renunță -> își primește partea
 let r=await b.cancelCardBookingCore(stripe,{uid:'P2'},'s1','leave');
 assert.strictEqual(r.refunded,11.25);
 assert.deepStrictEqual(refunds[0],{pi:'pi_P2',amount:1125,key:'leave_s1_pi_P2',rev:false});
 m=store['matches/s1']; assert.ok(!m.joinedUids.includes('P2')); assert.strictEqual(m.cardPayments.P2.refunded,11.25);
 assert.strictEqual(notifs('match_left').length,2);
 // P2 renunță din nou -> eroare
 await assert.rejects(b.cancelCardBookingCore(stripe,{uid:'P2'},'s1','leave'),e=>e.status===403);
 // decontare înainte de start -> nu (settleSplitPayments sare); simulăm startul
 m.date=past;
 const got=await b.settleSplit(stripe,docRef('matches/s1'),clone(store['matches/s1']));
 assert.strictEqual(got,11.25,'gazda primește doar partea lui P1 (P2 a renunțat)');
 assert.strictEqual(refunds[1].pi,'pi_H'); assert.strictEqual(refunds[1].amount,1125); assert.strictEqual(refunds[1].key,'reimburse_s1');
 m=store['matches/s1']; assert.strictEqual(m.hostReimbursed,true); assert.strictEqual(m.cardPayments.H.refunded,11.25);
 assert.strictEqual(notifs('split_reimbursed').length,1);
 // după start jucătorul nu mai poate renunța
 await assert.rejects(b.cancelCardBookingCore(stripe,{uid:'P1'},'s1','leave'),e=>e.status===409);

 // --- plafonul gazdei: toți 4 plătesc -> gazda primește 3 părți (33.75), nu mai mult
 store['matches/s2']={hostUid:'H',locationId:'V',date:future,startHour:18,endHour:19,price:40,maxPlayers:4,paymentMode:'split',paymentMethod:'Card',paymentStatus:'awaiting_payment',status:'open',joinedUids:['H','A','B','C'],joinedPlayers:[]};
 await b.confirmPayment(stripe,{id:'pi_H2',amount:4500,metadata:{kind:'booking',matchId:'s2',uid:'H'}});
 for(const u of ['A','B','C']) await b.confirmPayment(stripe,{id:'pi_'+u,amount:1125,metadata:{kind:'share',matchId:'s2',uid:u}});
 store['matches/s2'].date=past;
 assert.strictEqual(await b.settleSplit(stripe,docRef('matches/s2'),clone(store['matches/s2'])),33.75);

 // --- gazda anulează: toți primesc tot ce au plătit
 store['matches/s3']={hostUid:'H',hostUsername:'Gazda',locationId:'V',locationName:'sala',date:future,startHour:18,endHour:19,price:40,maxPlayers:2,paymentMode:'split',paymentMethod:'Card',paymentStatus:'awaiting_payment',status:'open',joinedUids:['H','X'],joinedPlayers:[{uid:'H',username:'Gazda'},{uid:'X',username:'Xu'}]};
 await b.confirmPayment(stripe,{id:'pi_H3',amount:4500,metadata:{kind:'booking',matchId:'s3',uid:'H'}});
 await b.confirmPayment(stripe,{id:'pi_X',amount:2250,metadata:{kind:'share',matchId:'s3',uid:'X'}});
 const before=refunds.length;
 await assert.rejects(b.cancelCardBookingCore(stripe,{uid:'X'},'s3','cancel'),e=>e.status===403,'jucătorul nu anulează tot');
 r=await b.cancelCardBookingCore(stripe,{uid:'H'},'s3','cancel');
 assert.strictEqual(r.refunded,45); assert.strictEqual(r.refundedTotal,67.5);
 assert.strictEqual(refunds.length-before,2);
 m=store['matches/s3']; assert.strictEqual(m.status,'cancelled'); assert.strictEqual(m.paymentStatus,'refunded'); assert.strictEqual(m.refundedAmount,67.5);
 assert.ok(notifs('match_cancel').some(n=>n.toUid==='X')&&notifs('match_cancel').some(n=>n.toUid==='V'));
 assert.ok(notifs('payment_refunded').some(n=>n.toUid==='X'&&n.args.amount==='22.50'));
 await assert.rejects(b.cancelCardBookingCore(stripe,{uid:'H'},'s3','cancel'),e=>e.status===409);
 // plata unei părți după anulare -> rambursare automată
 assert.strictEqual(await b.confirmPayment(stripe,{id:'pi_late',amount:2250,metadata:{kind:'share',matchId:'s3',uid:'X'}}),'invalid');

 // --- rezervare veche (fără registru), plătită integral: sala anulează după start -> returnează tot
 store['matches/old']={hostUid:'H',locationId:'V',date:past,startHour:10,endHour:11,price:30,paymentMethod:'Card',paymentStatus:'confirmed',status:'open',stripePaymentIntentId:'pi_old',paidAmount:35,joinedUids:['H']};
 await assert.rejects(b.cancelCardBookingCore(stripe,{uid:'H'},'old','cancel'),e=>e.status===409,'gazda nu anulează după start');
 r=await b.cancelCardBookingCore(stripe,{uid:'V'},'old','cancel');
 assert.strictEqual(r.refundedTotal,35);
 // reverse_transfer la sălile cu Stripe Connect
 pis['pi_conn']={id:'pi_conn',transfer_data:{destination:'acct_x'}};
 store['matches/c1']={hostUid:'H',locationId:'V',date:future,startHour:10,endHour:11,price:30,paymentMethod:'Card',paymentStatus:'awaiting_payment',status:'open',joinedUids:['H']};
 await b.confirmPayment(stripe,{id:'pi_conn',amount:3500,metadata:{kind:'booking',matchId:'c1',uid:'H'}});
 await b.cancelCardBookingCore(stripe,{uid:'H'},'c1','cancel');
 assert.strictEqual(refunds[refunds.length-1].rev,true);
 // parte prea mică (sub 2 RON)
 store['matches/tiny']={hostUid:'H',locationId:'V',date:future,startHour:10,endHour:11,price:10,maxPlayers:12,paymentMode:'split',paymentMethod:'Card',paymentStatus:'confirmed',status:'open',joinedUids:['H','Z']};
 await assert.rejects(b.purposeMetadata({kind:'share',matchId:'tiny'},'Z','V'),e=>e.status===409);
 // anulare silențioasă de către sală: bani înapoi, fără anunț dublu de la server
 store['matches/q1']={hostUid:'H',locationId:'V',date:future,startHour:10,endHour:11,price:30,paymentMethod:'Card',paymentStatus:'awaiting_payment',status:'open',joinedUids:['H']};
 await b.confirmPayment(stripe,{id:'pi_q1',amount:3500,metadata:{kind:'booking',matchId:'q1',uid:'H'}});
 const nBefore=notifs('match_cancel').length;
 r=await b.cancelCardBookingCore(stripe,{uid:'V'},'q1','cancel',{silent:true});
 assert.strictEqual(r.refundedTotal,35); assert.strictEqual(notifs('match_cancel').length,nBefore);
 // jucătorul nu poate cere „silent”
 store['matches/q2']={hostUid:'H',locationId:'V',date:future,startHour:10,endHour:11,price:30,paymentMethod:'Card',paymentStatus:'awaiting_payment',status:'open',joinedUids:['H','Y'],joinedPlayers:[]};
 await b.confirmPayment(stripe,{id:'pi_q2',amount:3500,metadata:{kind:'booking',matchId:'q2',uid:'H'}});
 const n2=notifs('match_cancel').length;
 await b.cancelCardBookingCore(stripe,{uid:'H'},'q2','cancel',{silent:true});
 assert.ok(notifs('match_cancel').length>n2,'gazda nu poate anula silențios');
 console.log('plata împărțită: toate verificările au trecut');
});
