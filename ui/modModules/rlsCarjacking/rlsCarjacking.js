// Decorate the add-on's actions without replacing RLS Vue pages.
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

  // RLS 2.8 has no per-vehicle chooser predicate for an unassigned world car.
  // Its stock Vue runtime exposes the owning component on rendered elements.
  // Read the selected row from that component; Lua rechecks eligibility both
  // before showing the action and when confirming it. Never infer IDs from names.
  const selectedVehicle = menu => {
    for (let component = menu.__vueParentComponent; component; component = component.parent) {
      const selected = component.setupState && component.setupState.vehSelected
      if (selected && Number.isSafeInteger(selected.id)) return selected
    }
    return null
  }
  // BngPopoverMenu sets inheritAttrs:false, so RLS's .veh-menu class never
  // reaches the DOM. Inspect its native element and identify VehicleList by
  // component state; other popovers have no selected inventory vehicle.
  const abandonMenus = new WeakMap()
  const decorateVehicleMenu = menu => {
    const vehicle = selectedVehicle(menu)
    // buttonsActive.sellEnabled distinguishes My Vehicles from trade-in and
    // other pickers that reuse VehicleList. No add-on action on those screens.
    let myVehicles = false
    for (let component = menu.__vueParentComponent; component; component = component.parent) {
      const store = component.setupState && component.setupState.vehicleInventoryStore
      if (store) {
        myVehicles = store.vehicleInventoryData?.buttonsActive?.sellEnabled === true
        break
      }
    }
    const id = vehicle && vehicle.id
    const eligible = myVehicles && vehicle?.owned === true && !vehicle.location
      && !vehicle.inStorage && !vehicle.inGarage && !vehicle.timeToAccess && !vehicle.listedForAuction
    const previous = abandonMenus.get(menu)
    if (!eligible) {
      if (previous?.button) previous.button.remove()
      abandonMenus.delete(menu)
      return
    }
    if (previous?.id === id) return
    if (previous?.button) previous.button.remove()
    const request = {id}
    abandonMenus.set(menu, request)
    if (!window.bngApi?.engineLua) return
    window.bngApi.engineLua(`career_modules_carjacking.canAbandonVehicle(${id})`, allowed => {
      if (!allowed || abandonMenus.get(menu) !== request || !menu.isConnected || selectedVehicle(menu)?.id !== id) return
      const nativeButton = menu.querySelector("button")
      if (!nativeButton) { abandonMenus.delete(menu); return }
      // Copy native HouseButton markup attributes for styling and navigation;
      // cloneNode does not copy its Vue event handlers or component state.
      const button = nativeButton.cloneNode(false)
      button.removeAttribute("id")
      button.removeAttribute("disabled")
      button.removeAttribute("aria-disabled")
      button.removeAttribute("bng-no-nav")
      button.classList.add("rls-carjacking-abandon")
      button.textContent = "Abandon"
      button.addEventListener("click", event => {
        event.stopPropagation()
        window.bngApi.engineLua(`career_modules_carjacking.abandonVehicle(${id})`)
      })
      request.button = button
      nativeButton.parentElement.appendChild(button)
    })
  }

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
    const menu = element.closest(".bng-popover-menu")
    if (menu) decorateVehicleMenu(menu)
    element.querySelectorAll(".bng-popover-menu").forEach(decorateVehicleMenu)
    // Selection can change without replacing the popover's DOM node.
    if (element.closest(".vehicle-list-container")) {
      document.querySelectorAll(".bng-popover-menu").forEach(decorateVehicleMenu)
    }
  }

  // React to menu rendering/vehicle selection, never poll or change callbacks.
  const observer = new MutationObserver(records => {
    for (const record of records) {
      if (record.type === "characterData") inspect(record.target)
      else {
        if (record.target.nodeType === 1) inspect(record.target)
        record.addedNodes.forEach(inspect)
      }
    }
  })
  observer.observe(document.body, {childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["class"]})
  inspect(document.body)
  window.addEventListener("pagehide", () => observer.disconnect(), {once: true})
})
