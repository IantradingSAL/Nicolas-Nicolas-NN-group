// auth_guard.js — page-load guard.
//
// This is a permissive stub for the fresh Nicolas Nicolas Group
// deployment: it does not enforce login yet, so every visitor can
// see the pages. It DOES kick off the audit logger so page views
// are still recorded (as user_id=null when no session exists).
//
// When you're ready to enforce login, replace the body of guard()
// with a real check against sb.auth.getSession() and a redirect
// to a login page.

import { SUPABASE_CONFIG } from './config.js'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { initAudit }     from './audit_log.js'

async function guard() {
  const sb = createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey)
  const { data } = await sb.auth.getSession().catch(() => ({ data: { session: null } }))
  const session = data?.session || null
  window.__SB = sb
  window.__USER = session?.user || null
  initAudit({ sb, user: window.__USER })
}
guard()
