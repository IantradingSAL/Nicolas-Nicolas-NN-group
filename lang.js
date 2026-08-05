// lang.js — i18n + help panel stub.
//
// The original app shipped English/French translations and a
// bottom-right help panel (CW_HELP.buildPanel + CW_HELP.init).
// Both are stubbed here so pages that reference them don't crash.
// Replace with real translations when needed.

window.CW_HELP = {
  buildPanel: () => '',
  init:       () => {},
}

window.T = (en /*, fr */) => en
