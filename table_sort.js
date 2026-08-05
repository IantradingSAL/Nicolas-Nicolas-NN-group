// table_sort.js — click-to-sort on <table thead th>.
//
// Sorts the visible rows of any <table> whose <th data-sortable>
// cells are clicked. Numeric columns are detected automatically.
// Original repo had a richer version; this is the minimum needed
// so pages that reference table_sort.js don't 404.

(function () {
  function cellVal(row, idx) {
    const td = row.children[idx]
    return td ? td.textContent.trim() : ''
  }
  function sortBy(table, idx, dir) {
    const tb = table.tBodies[0]; if (!tb) return
    const rows = Array.from(tb.rows)
    const numeric = rows.every(r => {
      const v = cellVal(r, idx).replace(/[^\d.\-]/g, '')
      return v === '' || !isNaN(Number(v))
    })
    rows.sort((a, b) => {
      const av = cellVal(a, idx), bv = cellVal(b, idx)
      if (numeric) return (Number(av.replace(/[^\d.\-]/g, '') || 0) - Number(bv.replace(/[^\d.\-]/g, '') || 0)) * dir
      return av.localeCompare(bv) * dir
    })
    rows.forEach(r => tb.appendChild(r))
  }
  document.addEventListener('click', (e) => {
    const th = e.target.closest('th[data-sortable]'); if (!th) return
    const table = th.closest('table'); if (!table) return
    const idx = Array.from(th.parentNode.children).indexOf(th)
    const cur = th.dataset.sortDir === 'asc' ? -1 : 1
    Array.from(th.parentNode.children).forEach(x => delete x.dataset.sortDir)
    th.dataset.sortDir = cur === 1 ? 'asc' : 'desc'
    sortBy(table, idx, cur)
  })
})();
