import { Controller } from "@hotwired/stimulus"

// Client-side seat selection: enforces the 6-seat max, tracks a running
// total, and enables/disables the "Hold seats" submit button. This is a
// convenience only — the backend re-validates everything (seat availability,
// max 6, trip ownership) inside a locked transaction regardless of what this
// controller allows through.
export default class extends Controller {
  static targets = ["checkbox", "selectedCount", "selectedList", "totalPrice", "submit", "limitWarning"]
  static values = { max: Number, price: Number }

  connect() {
    this.refresh()
  }

  toggle(event) {
    const checked = this.checkedBoxes()
    if (checked.length > this.maxValue) {
      event.target.checked = false
      this.showLimitWarning()
    }
    this.refresh()
  }

  checkedBoxes() {
    return this.checkboxTargets.filter((box) => box.checked)
  }

  refresh() {
    const checked = this.checkedBoxes()
    const seatNumbers = checked.map((box) => box.dataset.seatNumber)

    this.selectedCountTarget.textContent = `${checked.length}/${this.maxValue}`
    this.selectedListTarget.textContent = seatNumbers.length ? seatNumbers.join(", ") : "None selected"
    this.totalPriceTarget.textContent = (checked.length * this.priceValue).toFixed(0)
    this.submitTarget.disabled = checked.length === 0
    this.limitWarningTarget.classList.toggle("hidden", checked.length < this.maxValue)
  }

  showLimitWarning() {
    this.limitWarningTarget.classList.remove("hidden")
  }
}
