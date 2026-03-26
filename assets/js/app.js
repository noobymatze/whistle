// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

import ProseMirrorHook from "./prosemirror_hook"
import "./prosemirror_init"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let hooks = { ProseMirror: ProseMirrorHook }
let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks})

const setMobileMenuState = (root, isOpen) => {
  root.dataset.mobileMenuOpen = isOpen ? "true" : "false"
  document.documentElement.classList.toggle("overflow-hidden", isOpen)
  document.body.classList.toggle("overflow-hidden", isOpen)

  root.querySelectorAll("[data-mobile-menu-open]").forEach((button) => {
    button.setAttribute("aria-expanded", isOpen ? "true" : "false")
  })

  const panel = root.querySelector("[data-mobile-menu-panel]")
  if (panel) {
    panel.setAttribute("aria-hidden", isOpen ? "false" : "true")
  }
}

const bindMobileMenus = () => {
  document.querySelectorAll("[data-mobile-menu]").forEach((root) => {
    if (root.dataset.mobileMenuBound === "true") return
    root.dataset.mobileMenuBound = "true"

    const open = () => setMobileMenuState(root, true)
    const close = () => setMobileMenuState(root, false)

    root.querySelectorAll("[data-mobile-menu-open]").forEach((button) => {
      button.addEventListener("click", open)
    })

    root.querySelectorAll("[data-mobile-menu-close]").forEach((button) => {
      button.addEventListener("click", close)
    })

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") close()
    })

    window.addEventListener("resize", () => {
      if (window.innerWidth >= 768) close()
    })

    close()
  })
}

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()
bindMobileMenus()
window.addEventListener("phx:page-loading-stop", bindMobileMenus)

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
