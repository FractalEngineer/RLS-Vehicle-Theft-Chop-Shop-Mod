// RLS 2.7.1's computer uses a fixed icon-by-ID map and ignores Lua icon fields.
// Decorate only our Strip for Parts tile without replacing the RLS Vue page.
angular.module("rlsCarjacking", []).run(() => {
  const style = document.createElement("style")
  style.textContent = `
    .computer-function-tile .icon.rls-carjacking-strip-icon {
      display: inline-block;
      width: 1em;
      height: 1em;
      color: transparent;
      background-color: #fff;
      -webkit-mask: url('/ui/modModules/rlsCarjacking/icons/strip_for_parts.svg') center / contain no-repeat;
      mask: url('/ui/modModules/rlsCarjacking/icons/strip_for_parts.svg') center / contain no-repeat;
    }
  `
  document.head.appendChild(style)

  const decorate = tile => {
    const label = tile.querySelector(".label")
    const icon = tile.querySelector(".icon")
    if (icon) icon.classList.toggle("rls-carjacking-strip-icon",
      !!label && /^Strip for Parts \([\d.]+% value\)$/.test(label.textContent.trim()))
  }
  const inspect = node => {
    const element = node.nodeType === 1 ? node : node.parentElement
    if (!element) return
    const tile = element.closest(".computer-function-tile")
    if (tile) decorate(tile)
    element.querySelectorAll(".computer-function-tile").forEach(decorate)
  }

  // React to menu rendering/vehicle selection, never poll or change callbacks.
  const observer = new MutationObserver(records => {
    for (const record of records) {
      if (record.type === "characterData") inspect(record.target)
      else {
        if (record.target.nodeType === 1 && record.target.closest(".computer-function-tile")) inspect(record.target)
        record.addedNodes.forEach(inspect)
      }
    }
  })
  observer.observe(document.body, {childList: true, subtree: true, characterData: true})
  inspect(document.body)
  window.addEventListener("pagehide", () => observer.disconnect(), {once: true})
})
