// csv_export.js — tiny helper for browser-side CSV downloads.
//
// downloadCsv(filename, columns, rows) triggers a file download.
// Each column is { header: string, get: (row) => any }.

export function todayIso() {
  return new Date().toISOString().slice(0, 10)
}

function escapeCell(v) {
  if (v == null) return ''
  const s = String(v)
  if (/[",\n\r]/.test(s)) return '"' + s.replace(/"/g, '""') + '"'
  return s
}

export function downloadCsv(filename, columns, rows) {
  const header = columns.map(c => escapeCell(c.header)).join(',')
  const body = rows.map(r => columns.map(c => escapeCell(c.get(r))).join(',')).join('\n')
  const csv = header + '\n' + body
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}
