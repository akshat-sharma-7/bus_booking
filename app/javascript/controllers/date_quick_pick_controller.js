import { Controller } from "@hotwired/stimulus"

// "Today" / "Tomorrow" set the date field to the BROWSER's local date (not
// UTC — Date#toISOString() is UTC and can land on the wrong calendar day
// near midnight in timezones ahead of UTC) and submit immediately.
// "Select Date" just opens/focuses the native date picker so the user can
// pick something else, then submit manually via the Search button.
export default class extends Controller {
  static targets = ["input"]

  today() {
    this.setDate(new Date())
  }

  tomorrow() {
    const date = new Date()
    date.setDate(date.getDate() + 1)
    this.setDate(date)
  }

  selectDate() {
    if (this.inputTarget.showPicker) {
      this.inputTarget.showPicker()
    } else {
      this.inputTarget.focus()
    }
  }

  setDate(date) {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    this.inputTarget.value = `${year}-${month}-${day}`
    this.inputTarget.form.requestSubmit()
  }
}
