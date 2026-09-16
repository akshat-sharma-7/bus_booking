import { Controller } from "@hotwired/stimulus"

// Purely cosmetic countdown — it can drift, the tab can be throttled in the
// background, or the user's clock can be wrong. The actual "is this hold
// still valid" check happens server-side, inside a locked transaction,
// against the database's expires_at every time. When this countdown hits
// zero we just disable the button and tell the user — we don't rely on it
// to prevent an expired confirmation from going through.
export default class extends Controller {
  static targets = ["display", "confirmButton", "expiredMessage"]
  static values = { expiresAt: String, reloadUrl: String }

  connect() {
    this.tick()
    this.interval = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.interval)
  }

  tick() {
    const remainingMs = new Date(this.expiresAtValue).getTime() - Date.now()

    if (remainingMs <= 0) {
      this.displayTarget.textContent = "00:00"
      this.confirmButtonTarget.disabled = true
      this.expiredMessageTarget.classList.remove("hidden")
      clearInterval(this.interval)
      // Reload so the server (the actual authority on expiry) re-renders
      // this page — it'll show the "hold expired" state, or, if the
      // background job hasn't processed the expiry yet, the show action's
      // own expires_at check still treats it as expired regardless of the
      // Hold row's stored status. Brief delay so the message above is
      // actually visible before the page changes.
      setTimeout(() => { window.location.href = this.reloadUrlValue || window.location.href }, 1500)
      return
    }

    const totalSeconds = Math.floor(remainingMs / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    this.displayTarget.textContent = `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
  }
}
