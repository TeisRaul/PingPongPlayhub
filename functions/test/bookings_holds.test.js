// Teste pentru plata cu cardul (functions/bookings.js), cu Firestore și Stripe simulate.
const test=require('node:test');
const Module=require('module');const store={};
function docRef(p){return{path:p,id:p.split('/').pop(),async get(){return snap(p)},async set(d,o){store[p]=o&&o.merge?{...(store[p]||{}),...d}:d},async update(d){store[p]={...store[p],...d}},async delete(){delete store[p]},collection(c){return col(p+'/'+c)}}}
function snap(p){return{exists:p in store,id:p.split('/').pop(),data:()=>store[p]&&{...store[p]},ref:docRef(p)}}
function col(c){return{doc:id=>docRef(c+'/'+id),async add(d){const id='n'+Math.random();store[c+'/'+id]=d},where(f,op,v){return{async get(){const docs=Object.keys(store).filter(k=>k.startsWith(c+'/')&&store[k][f]===v).map(snap);return{docs}}}}}}
const db={collection:col,async runTransaction(fn){return fn({get:r=>r.get(),update:(r,d)=>{store[r.path]={...store[r.path],...d}}})}};
const admin={firestore:Object.assign(()=>db,{FieldValue:{serverTimestamp:()=>'TS'}})};
const sessions={cs_old:{status:'open',payment_status:'unpaid'},cs_paid:{status:'complete',payment_status:'paid',payment_intent:'pi_paid'}};
const fakeStripe={checkout:{sessions:{async retrieve(id){return{...sessions[id]}},async expire(id){sessions[id].status='expired';return{...sessions[id]}}}},
 paymentIntents:{async retrieve(id){return id==='pi_paid'?{id,amount:3500,status:'succeeded',metadata:{kind:'booking',matchId:'m_paid',uid:'u1'}}:{id,status:'requires_payment_method',metadata:{}}},async cancel(id){canceled.push(id)}},
 refunds:{async create(){throw new Error('nu trebuia rambursare')}}};
const canceled=[];
const orig=Module._load;Module._load=function(r){if(r==='firebase-admin')return admin;if(r==='firebase-functions/v2/scheduler')return{onSchedule:(o,f)=>f};if(r==='firebase-functions/v2/https')return{onRequest:(o,f)=>f};if(r==='firebase-functions/params')return{defineSecret:()=>({value:()=>'sk'})};if(r==='stripe')return()=>fakeStripe;return orig.apply(this,arguments)};
const b=require('../bookings.js');const assert=require('assert');
const old={toMillis:()=>Date.now()-60*60000}, fresh={toMillis:()=>Date.now()-5*60000};
store['matches/m_old']={paymentStatus:'awaiting_payment',createdAt:old,checkoutSessionId:'cs_old'};
store['matches/m_pi']={paymentStatus:'awaiting_payment',createdAt:old,paymentIntentId:'pi_x'};
store['matches/m_fresh']={paymentStatus:'awaiting_payment',createdAt:fresh};
store['matches/m_paid']={paymentStatus:'awaiting_payment',createdAt:old,checkoutSessionId:'cs_paid'};
store['matches/m_cash']={paymentStatus:'pending',createdAt:old};
test('rezervări neplătite: eliberare sau confirmare târzie',async()=>{await b.releaseUnpaidHolds();
 assert.ok(!('matches/m_old' in store),'old checkout hold sters');
 assert.strictEqual(sessions.cs_old.status,'expired');
 assert.ok(!('matches/m_pi' in store)); assert.deepStrictEqual(canceled,['pi_x']);
 assert.ok('matches/m_fresh' in store,'hold recent pastrat');
 assert.strictEqual(store['matches/m_paid'].paymentStatus,'confirmed','plata tarzie confirmata');
 assert.ok('matches/m_cash' in store);
 console.log('releaseUnpaidHolds: ok');});
