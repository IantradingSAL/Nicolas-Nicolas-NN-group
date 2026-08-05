// access.js — page-level access flags.
//
// Permissive stub. Every page is allowed for every visitor until
// you wire real role checks against role_templates + employees.
// The original app used this file to hide UI based on PAGE_KEY;
// here we simply mark the page as fully accessible.

(function () {
  const key = (typeof PAGE_KEY !== 'undefined') ? PAGE_KEY : (location.pathname.split('/').pop() || 'index')
  window.ACCESS = {
    page: key,
    can:  () => true,
    role: 'guest',
  }
})();
