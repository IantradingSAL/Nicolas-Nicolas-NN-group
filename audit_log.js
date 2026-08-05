// audit_log.js — every-user, every-action trace logger.
//
// Records:
//   * page_view          — one row per page load
//   * heartbeat          — one row every 30s while the tab is open,
//                          so idle sessions still produce a trace
//   * click              — every click on a button, link, or input
//   * form_submit        — every form submission
//   * db_write           — every insert / update / delete on Supabase,
//                          captured by wrapping window.__SB.from()
//   * auth               — sign-in and sign-out events
//   * page_hide / page_show — tab visibility changes
//   * unload             — page close (best-effort via sendBeacon)
//
// Writes go to the public.audit_log table (see schema.sql). If Supabase
// isn't configured yet, events queue in localStorage under
// 'nn_audit_queue' and flush automatically once a real client is ready.

const QUEUE_KEY = 'nn_audit_queue'
const SESSION_KEY = 'nn_audit_session'
const HEARTBEAT_MS = 30_000
const FLUSH_BATCH = 25

let _sb = null
let _user = null
let _sessionId = null
let _flushing = false
let _pageKey = null

function newId() {
  // RFC 4122-ish v4 without the crypto dep so it works offline too.
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0
    const v = c === 'x' ? r : (r & 0x3 | 0x8)
    return v.toString(16)
  })
}

function getSessionId() {
  let id = sessionStorage.getItem(SESSION_KEY)
  if (!id) { id = newId(); sessionStorage.setItem(SESSION_KEY, id) }
  return id
}

function readQueue() {
  try { return JSON.parse(localStorage.getItem(QUEUE_KEY) || '[]') }
  catch { return [] }
}
function writeQueue(q) {
  try { localStorage.setItem(QUEUE_KEY, JSON.stringify(q.slice(-500))) } catch {}
}

function enqueue(event) {
  const row = {
    id:         newId(),
    session_id: _sessionId,
    user_id:    _user?.id || null,
    user_email: _user?.email || null,
    page:       _pageKey,
    action:     event.action,
    target:     event.target || null,
    detail:     event.detail || null,
    url:        location.pathname + location.hash,
    user_agent: navigator.userAgent,
    created_at: new Date().toISOString(),
  }
  const q = readQueue()
  q.push(row)
  writeQueue(q)
  flush()  // fire-and-forget
}

async function flush() {
  if (_flushing) return
  if (!_sb) return
  const q = readQueue()
  if (!q.length) return
  _flushing = true
  try {
    const batch = q.slice(0, FLUSH_BATCH)
    const { error } = await _sb.from('audit_log').insert(batch)
    if (error) {
      // Placeholder Supabase / missing table / RLS block — keep in queue,
      // stop hammering the console.
      if (!window.__auditWarned) {
        console.info('[audit] queued locally (supabase write failed):', error.message)
        window.__auditWarned = true
      }
    } else {
      writeQueue(q.slice(batch.length))
      if (readQueue().length) { setTimeout(flush, 200) }
    }
  } catch (e) {
    if (!window.__auditWarned) {
      console.info('[audit] queued locally (network error):', e.message)
      window.__auditWarned = true
    }
  } finally {
    _flushing = false
  }
}

function wrapSupabaseWrites(sb) {
  if (!sb || sb.__auditWrapped) return sb
  const origFrom = sb.from.bind(sb)
  sb.from = (table) => {
    const q = origFrom(table)
    for (const op of ['insert', 'update', 'delete', 'upsert']) {
      const orig = q[op]
      if (typeof orig !== 'function') continue
      q[op] = function (...args) {
        try {
          enqueue({
            action: 'db_write',
            target: `${table}.${op}`,
            detail: summarize(args[0]),
          })
        } catch {}
        return orig.apply(this, args)
      }
    }
    return q
  }
  sb.__auditWrapped = true
  return sb
}

function summarize(payload) {
  if (payload == null) return null
  try {
    const s = JSON.stringify(payload)
    return s.length > 500 ? s.slice(0, 500) + '…' : s
  } catch { return String(payload) }
}

function elDescriptor(el) {
  if (!el || !el.tagName) return null
  const parts = [el.tagName.toLowerCase()]
  if (el.id) parts.push('#' + el.id)
  if (el.name) parts.push(`[name=${el.name}]`)
  const text = (el.innerText || el.value || '').trim().slice(0, 40)
  if (text) parts.push(`"${text}"`)
  return parts.join('')
}

function attachDomHooks() {
  // Every click on an actionable control.
  document.addEventListener('click', (e) => {
    const t = e.target.closest('button, a, [role="button"], input[type=submit], input[type=checkbox], input[type=radio]')
    if (!t) return
    enqueue({ action: 'click', target: elDescriptor(t) })
  }, true)

  // Form submissions.
  document.addEventListener('submit', (e) => {
    enqueue({ action: 'form_submit', target: elDescriptor(e.target) })
  }, true)

  // Tab visibility — captures "user is watching but not doing anything".
  document.addEventListener('visibilitychange', () => {
    enqueue({ action: document.hidden ? 'page_hide' : 'page_show' })
  })

  // Page close — best-effort via sendBeacon so nothing is dropped on nav.
  window.addEventListener('pagehide', () => {
    enqueue({ action: 'unload' })
    // We can't reliably POST here; the queue will drain on the next page.
  })
}

function startHeartbeat() {
  setInterval(() => {
    if (document.hidden) return  // don't heartbeat while tab is hidden
    enqueue({ action: 'heartbeat' })
  }, HEARTBEAT_MS)
}

export function initAudit({ sb, user }) {
  if (window.__auditInited) return
  window.__auditInited = true

  _sb = wrapSupabaseWrites(sb)
  _user = user || null
  _sessionId = getSessionId()
  _pageKey = (typeof PAGE_KEY !== 'undefined')
    ? PAGE_KEY
    : (location.pathname.split('/').pop() || 'index').replace(/\.html$/, '')

  enqueue({ action: 'page_view', detail: document.title })

  attachDomHooks()
  startHeartbeat()

  // React to sign-in/out.
  if (sb?.auth?.onAuthStateChange) {
    sb.auth.onAuthStateChange((event, session) => {
      _user = session?.user || null
      enqueue({ action: 'auth', target: event, detail: _user?.email || null })
    })
  }

  // Periodic flush attempt (in case config.js was populated later).
  setInterval(flush, 10_000)
}
