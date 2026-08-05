// auth_guard.js — page-load guard.
//
// Runs on every protected page. If no Supabase session, bounces the
// browser to login.html?next=<current-page>. Otherwise exposes the
// signed-in user on window.__USER and kicks off the audit logger so
// every action is traced under that user's id.
//
// login.html itself is not guarded (skip on that file).

import { SUPABASE_CONFIG } from './config.js'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { initAudit }     from './audit_log.js'

const sb = createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey)
window.__SB = sb

async function guard() {
  const here = (location.pathname.split('/').pop() || 'index.html').toLowerCase()
  if (here === 'login.html') return   // login page handles itself

  const { data, error } = await sb.auth.getSession().catch(e => ({ data: { session: null }, error: e }))
  const session = data?.session || null

  if (!session) {
    const next = encodeURIComponent(location.pathname.split('/').pop() + location.search + location.hash)
    location.replace('login.html?next=' + next)
    return
  }

  window.__USER = session.user
  initAudit({ sb, user: session.user })

  // Bounce back to login when the session ends (sign-out from any tab, token expiry, etc.).
  sb.auth.onAuthStateChange((event, s) => {
    if (event === 'SIGNED_OUT' || !s) location.replace('login.html')
  })
}
guard()

// Small helper any page can call from a Sign Out button.
window.signOut = async () => {
  await sb.auth.signOut()
  location.replace('login.html')
}
