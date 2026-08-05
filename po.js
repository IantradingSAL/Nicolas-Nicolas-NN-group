// po.js — purchase-order helpers for the inventory page.
//
// Groups requisition line items by preferred supplier, creates one
// purchase_orders row per supplier + its purchase_order_lines, and
// (best-effort) emails the supplier via a Supabase edge function
// named `send-brevo`. In this fresh NN deployment the edge function
// doesn't exist yet, so email fails soft and the PO is still recorded
// with email_status = 'no_email' or 'failed'. Wire the edge function
// (or replace this call) when you're ready to send real emails.

function newPoNumber() {
  const t = new Date()
  const stamp = t.toISOString().replace(/[-:T]/g,'').slice(0,12)
  const rand  = Math.floor(Math.random() * 900 + 100)
  return `PO-${stamp}-${rand}`
}

async function fetchItemSupplierMap(sb, itemNames) {
  if (!itemNames.length) return { map: {}, suppliers: {} }
  const { data: items } = await sb.from('inventory_items')
    .select('id,item_name,name,preferred_supplier_id')
    .in('name', itemNames)
  const bySupplier = {}
  const itemToSup  = {}
  ;(items || []).forEach(it => {
    const nm = it.item_name || it.name
    if (it.preferred_supplier_id) itemToSup[nm] = it.preferred_supplier_id
  })
  const supIds = [...new Set(Object.values(itemToSup))]
  const { data: sups } = supIds.length
    ? await sb.from('suppliers').select('id,name,email,contact_email,cc_emails').in('id', supIds)
    : { data: [] }
  const suppliers = {}
  ;(sups || []).forEach(s => { suppliers[s.id] = s })
  return { map: itemToSup, suppliers }
}

export async function createAndEmailPOs(sb, items, opts = {}) {
  const { source = 'inventory_queue', createdBy = 'System' } = opts
  const names = [...new Set(items.map(i => i.item_name))]
  const { map, suppliers } = await fetchItemSupplierMap(sb, names)

  // Group items by supplier id (skip items without a preferred supplier).
  const groups = {}
  const noSupplier = []
  for (const it of items) {
    const supId = map[it.item_name]
    if (!supId) { noSupplier.push(it); continue }
    ;(groups[supId] ||= []).push(it)
  }

  const pos = []
  const failed = []
  let emailed = 0

  for (const [supId, groupItems] of Object.entries(groups)) {
    const sup = suppliers[supId] || {}
    const supEmail = sup.email || sup.contact_email || null
    const poNumber = newPoNumber()
    const insertPo = {
      po_number: poNumber,
      supplier_id: supId,
      supplier_name: sup.name || null,
      supplier_email: supEmail,
      item_count: groupItems.length,
      total_cost: 0,
      status: 'sent',
      email_status: supEmail ? 'pending' : 'no_email',
      source, created_by: createdBy,
    }
    const { data: po, error: poErr } = await sb.from('purchase_orders').insert([insertPo]).select().single()
    if (poErr) { failed.push({ supplier: sup.name, error: poErr.message }); continue }

    const lines = groupItems.map(it => ({
      po_id: po.id,
      item_name: it.item_name,
      quantity: Number(it.quantity) || 0,
      unit: it.unit || null,
      unit_cost: 0,
      line_total: 0,
    }))
    await sb.from('purchase_order_lines').insert(lines)

    let emailStatus = supEmail ? 'sent' : 'no_email'
    if (supEmail) {
      try {
        const subject = `Purchase Order ${poNumber} — Nicolas Nicolas Group`
        const body = groupItems.map(i => `- ${i.item_name}: ${i.quantity}${i.unit ? ' ' + i.unit : ''}`).join('\n')
        const { error: fnErr } = await sb.functions.invoke('send-brevo', {
          body: { channel: 'email', to: supEmail, toName: sup.name || '', subject,
                  htmlContent: `<p>Please supply the following:</p><pre>${body}</pre>`, type: 'po' }
        })
        if (fnErr) emailStatus = 'failed'
        else emailed += 1
      } catch { emailStatus = 'failed' }
    }
    await sb.from('purchase_orders').update({ email_status: emailStatus }).eq('id', po.id)

    pos.push({ id: po.id, po_number: poNumber, refIds: groupItems.map(i => i.ref_id).filter(Boolean) })
  }

  return { pos, emailed, noSupplier, failed }
}

export async function resendPO(sb, poId) {
  const { data: po } = await sb.from('purchase_orders').select('*').eq('id', poId).single()
  if (!po?.supplier_email) return { ok: false, error: 'No supplier email on file' }
  const { data: lines } = await sb.from('purchase_order_lines').select('*').eq('po_id', poId)
  const body = (lines || []).map(l => `- ${l.item_name}: ${l.quantity}${l.unit ? ' ' + l.unit : ''}`).join('\n')
  try {
    const { error } = await sb.functions.invoke('send-brevo', {
      body: { channel: 'email', to: po.supplier_email, toName: po.supplier_name || '',
              subject: `Purchase Order ${po.po_number} (re-send) — Nicolas Nicolas Group`,
              htmlContent: `<p>Re-sending purchase order:</p><pre>${body}</pre>`, type: 'po' }
    })
    if (error) { await sb.from('purchase_orders').update({ email_status: 'failed' }).eq('id', poId); return { ok: false, error: error.message } }
    await sb.from('purchase_orders').update({ email_status: 'sent' }).eq('id', poId)
    return { ok: true }
  } catch (e) { return { ok: false, error: e.message } }
}

export async function reorderPO(sb, poId, opts = {}) {
  const { data: po } = await sb.from('purchase_orders').select('*').eq('id', poId).single()
  const { data: lines } = await sb.from('purchase_order_lines').select('*').eq('po_id', poId)
  if (!po || !lines?.length) return { ok: false, error: 'PO or lines missing' }
  const items = lines.map(l => ({ item_name: l.item_name, quantity: l.quantity, unit: l.unit }))
  const res = await createAndEmailPOs(sb, items, { source: 'reorder', createdBy: opts.createdBy || 'Manager' })
  const first = res.pos[0]
  if (!first) return { ok: false, error: 'No supplier match to reorder' }
  return { ok: true, po_number: first.po_number, emailStatus: res.emailed ? 'sent' : 'no_email' }
}
