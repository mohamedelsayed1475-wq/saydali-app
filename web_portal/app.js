// ═══════════════════════════════════════════════════════════════
//  كل صيدلية تستخدم السحابة الخاصة بها (Supabase).
//  - يمكن لكل صيدلية كتابة بيانات السحابة الخاصة بها أدناه مباشرة.
//  - إذا كانت الصفحة مستضافة على Supabase Storage، سيتم كشف العنوان تلقائياً.
// ═══════════════════════════════════════════════════════════════

// ── إعدادات Supabase الخاصة بالصيدلية (قم بتعديلها هنا إذا كنت تستضيف الصفحة بنفسك) ──
let SUPABASE_URL = ''; 
let SUPABASE_KEY = ''; 

// ── قراءة المعاملات من الرابط ──────────────────────────────────
const _params = new URLSearchParams(window.location.search);
const SESSION_CODE = (_params.get('code') || '').trim().toUpperCase();

// 1. الكشف التلقائي إذا كانت الصفحة مستضافة على Supabase Storage الخاص بالصيدلية
const hostname = window.location.hostname;
if (hostname.endsWith('.supabase.co') || hostname.endsWith('.supabase.net')) {
  SUPABASE_URL = window.location.origin + '/rest/v1';
}

const SUPABASE_BASE = SUPABASE_URL.replace('/rest/v1', '');
const HEADERS = {
  'apikey': SUPABASE_KEY,
  'Authorization': `Bearer ${SUPABASE_KEY}`,
  'Content-Type': 'application/json',
  'Prefer': 'return=representation',
};

// ── State ────────────────────────────────────────────────────
let sessionData  = null;
let sessionItems = [];
let responses    = {}; // { itemId: {...} }

// ── Helpers ──────────────────────────────────────────────────
const $ = id => document.getElementById(id);
function show(id) { $(id).style.display = 'flex'; }
function hide(id) { $(id).style.display = 'none'; }
function hideAll() {
  ['loading-screen','nocode-screen','error-screen','expired-screen',
   'responded-screen','success-screen','main-screen','submit-bar'].forEach(hide);
}
function generateCode(n=8) {
  const c='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return Array.from({length:n},()=>c[Math.floor(Math.random()*c.length)]).join('');
}

// ── API ──────────────────────────────────────────────────────
async function apiGet(path) {
  const r = await fetch(SUPABASE_URL + path, { headers: HEADERS });
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${await r.text()}`);
  return r.json();
}
async function apiPost(path, body) {
  const r = await fetch(SUPABASE_URL + path, { method:'POST', headers:HEADERS, body:JSON.stringify(body) });
  if (!r.ok) throw new Error(`POST ${path} → ${r.status}: ${await r.text()}`);
  return r.json();
}
async function apiPatch(path, body) {
  await fetch(SUPABASE_URL + path, { method:'PATCH', headers:HEADERS, body:JSON.stringify(body) });
}

// ── INIT ─────────────────────────────────────────────────────
async function init() {
  if (!SESSION_CODE) { hideAll(); show('nocode-screen'); return; }

  try {
    const sessions = await apiGet(
      `/rep_sessions?session_code=eq.${encodeURIComponent(SESSION_CODE)}&select=*`
    );

    if (!sessions || sessions.length === 0) {
      hideAll();
      $('error-message').textContent = `لم يتم العثور على الجلسة (${SESSION_CODE}). تأكد من الرابط.`;
      show('error-screen'); return;
    }

    sessionData = sessions[0];

    // منتهية؟
    if (sessionData.status !== 'responded' && new Date(sessionData.expires_at) < new Date()) {
      hideAll(); show('expired-screen'); return;
    }

    // تم الرد مسبقاً؟
    if (sessionData.status === 'responded') {
      hideAll();
      $('renew-btn').onclick = () => requestRenewal(SESSION_CODE);
      show('responded-screen'); return;
    }

    // جلب الأصناف
    sessionItems = await apiGet(
      `/session_items?session_id=eq.${sessionData.id}&is_private=eq.0&select=*`
    );

    // بناء الواجهة
    renderForm();

  } catch(err) {
    console.error(err);
    hideAll();
    $('error-message').textContent = `فشل تحميل البيانات. تأكد من اتصال الإنترنت أو إعدادات السيرفر. (${err.message})`;
    show('error-screen');
  }
}

// ── RENDER ───────────────────────────────────────────────────
function renderForm() {
  hideAll();
  $('pharm-name').textContent = sessionData.pharmacy_name || 'صيدلية غير محددة';
  $('rep-name').textContent   = sessionData.rep_name || 'مندوب';
  $('currency').textContent   = sessionData.currency || 'ج.م';
  $('items-count').textContent = sessionItems.length;
  $('total-count').textContent = sessionItems.length;

  const list = $('items-list');
  list.innerHTML = '';

  sessionItems.forEach((item, idx) => {
    // تهيئة حالة الرد
    responses[item.id] = {
      item_id:         item.id,
      is_available:    null,
      quantity:        '',
      price:           '',
      discount:        '',
      rep_notes:       '',
      rep_alternative: ''
    };

    const card = document.createElement('div');
    card.className = 'item-card';
    card.id = `card-${item.id}`;

    card.innerHTML = `
      <div class="item-header" onclick="toggleDetails(${item.id})">
        <div class="item-num">${idx + 1}</div>
        <div class="item-info">
          <div class="item-name">${esc(item.name)}</div>
          <div class="item-sub">الكمية المطلوبة: ${item.quantity || 1}</div>
        </div>
        <div class="avail-btns" onclick="event.stopPropagation()">
          <button class="tbtn tbtn-yes" id="btn-yes-${item.id}" onclick="setAvailable(${item.id}, true)">متوفر</button>
          <button class="tbtn tbtn-no" id="btn-no-${item.id}" onclick="setAvailable(${item.id}, false)">ناقص</button>
        </div>
      </div>

      <div class="item-details" id="details-${item.id}">
        <div class="fields-grid" id="fields-${item.id}"></div>
      </div>
    `;

    list.appendChild(card);
  });

  show('main-screen');
  show('submit-bar');
  updateProgress();
}

// ── ACTIONS ──────────────────────────────────────────────────
window.toggleDetails = function(itemId) {
  const det = $(`details-${itemId}`);
  det.classList.toggle('open');
}

window.setAvailable = function(itemId, isAvail) {
  responses[itemId].is_available = isAvail;

  const card = $(`card-${itemId}`);
  const btnYes = $(`btn-yes-${itemId}`);
  const btnNo = $(`btn-no-${itemId}`);

  if (isAvail) {
    card.className = 'item-card avail';
    btnYes.classList.add('on');
    btnNo.classList.remove('on');
    buildFields(itemId, true);
  } else {
    card.className = 'item-card unavail';
    btnYes.classList.remove('on');
    btnNo.classList.add('on');
    buildFields(itemId, false);
  }

  // فتح التفاصيل تلقائياً عند التحديد لتسهيل الإدخال
  $(`details-${itemId}`).classList.add('open');
  
  updateProgress();
}

function buildFields(itemId, isAvail) {
  const container = $(`fields-${itemId}`);
  container.innerHTML = '';

  if (isAvail) {
    container.innerHTML = `
      <div class="fg">
        <div class="flabel">الكمية المتاحة</div>
        <input type="number" class="finput" placeholder="الكمية" oninput="updateVal(${itemId}, 'quantity', this.value)" />
      </div>
      <div class="fg">
        <div class="flabel">السعر المقترح</div>
        <input type="number" step="0.01" class="finput" placeholder="السعر" oninput="updateVal(${itemId}, 'price', this.value)" />
      </div>
      <div class="fg">
        <div class="flabel">الخصم (%)</div>
        <input type="number" class="finput" placeholder="الخصم" oninput="updateVal(${itemId}, 'discount', this.value)" />
      </div>
      <div class="fg">
        <div class="flabel">ملاحظاتك</div>
        <input type="text" class="finput finput-rtl" placeholder="ملاحظات" oninput="updateVal(${itemId}, 'rep_notes', this.value)" />
      </div>
    `;
  } else {
    container.innerHTML = `
      <div class="fg full">
        <div class="flabel">البديل المقترح (اختياري)</div>
        <input type="text" class="finput finput-rtl" placeholder="اسم الدواء البديل والتركيز..." oninput="updateVal(${itemId}, 'rep_alternative', this.value)" />
      </div>
      <div class="fg full">
        <div class="flabel">سبب عدم التوفر / ملاحظة</div>
        <input type="text" class="finput finput-rtl" placeholder="ملاحظات" oninput="updateVal(${itemId}, 'rep_notes', this.value)" />
      </div>
    `;
  }
}

window.updateVal = function(itemId, field, val) {
  responses[itemId][field] = val;
}

function updateProgress() {
  const total    = sessionItems.length;
  const answered = Object.values(responses).filter(r => r.is_available !== null).length;
  const pct      = total > 0 ? Math.round(answered/total*100) : 0;
  $('prog-text').textContent = `${answered} / ${total}`;
  $('prog-fill').style.width = pct + '%';
  $('submit-btn').disabled   = answered < total;
}

// ── SUBMIT ───────────────────────────────────────────────────
window.submitResponse = async function() {
  const unanswered = sessionItems.filter(i => responses[i.id]?.is_available === null);
  if (unanswered.length) { alert(`يرجى تحديد توفر ${unanswered.length} صنف لم يُرد عليه`); return; }

  const btn = $('submit-btn');
  btn.disabled = true;
  btn.classList.add('loading');

  try {
    // 1. تحديث كل صنف
    for (const item of sessionItems) {
      const r = responses[item.id];
      await apiPatch(
        `/session_items?id=eq.${item.id}&session_id=eq.${sessionData.id}`,
        {
          is_available:    r.is_available ? 1 : 0,
          quantity:        r.quantity  ? Number(r.quantity)  : 0,
          price:           r.price     ? Number(r.price)     : 0,
          discount:        r.discount  ? Number(r.discount)  : 0,
          rep_notes:       r.rep_notes || '',
          rep_alternative: r.rep_alternative || ''
        }
      );
    }

    // 2. تحديث حالة الجلسة
    await apiPatch(`/rep_sessions?id=eq.${sessionData.id}`, {
      status: 'responded',
      responded_at: new Date().toISOString()
    });

    // 3. توليد كود الاستلام وحفظه
    const responseCode = generateCode(8);
    await apiPost('/response_codes', { response_code: responseCode, session_id: sessionData.id });

    // 4. عرض شاشة النجاح
    hideAll();
    $('code-display').textContent = responseCode;
    show('success-screen');

    $('copy-btn').onclick = () => {
      navigator.clipboard.writeText(responseCode)
        .then(() => { $('copy-btn').innerHTML='<span>✅</span><span>تم النسخ!</span>'; setTimeout(()=>{ $('copy-btn').innerHTML='<span>📋</span><span>نسخ الكود</span>'; },2000); })
        .catch(() => alert('كود الاستلام: ' + responseCode));
    };

  } catch(err) {
    console.error(err);
    btn.disabled = false;
    btn.classList.remove('loading');
    alert('خطأ أثناء الإرسال:\n' + err.message + '\n\nتحقق من الإنترنت وأعد المحاولة.');
  }
}

// ── RENEWAL ──────────────────────────────────────────────────
async function requestRenewal(code) {
  const btn = $('renew-btn');
  btn.disabled = true; btn.textContent = 'جاري الإرسال...';
  try {
    await fetch(`${SUPABASE_BASE}/functions/v1/submit-response`, {
      method:'POST', headers:{...HEADERS,'Content-Type':'application/json'},
      body: JSON.stringify({ action:'renew', session_code:code })
    });
    btn.textContent = '✅ تم إرسال طلب التجديد';
  } catch(e) {
    btn.textContent = '❌ فشل — حاول مجدداً'; btn.disabled = false;
  }
}

function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── START ────────────────────────────────────────────────────
init();
