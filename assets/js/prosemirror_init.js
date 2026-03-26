import { initEditor } from "./prosemirror_hook"

// Auto-initialize all ProseMirror editors on the page
function initAllEditors() {
  document.querySelectorAll("[data-prosemirror]").forEach(el => {
    if (!el._prosemirrorView) {
      el._prosemirrorView = initEditor(el)
    }
  })
}

// Initialize on DOMContentLoaded (regular pages)
document.addEventListener("DOMContentLoaded", initAllEditors)

// Export for dynamic use (e.g., adding a new choice)
window.initProseMirrorEditor = function(el) {
  if (!el._prosemirrorView) {
    el._prosemirrorView = initEditor(el)
  }
}

function buildChoiceRow(idx) {
  const div = document.createElement("div")
  div.className = "choice-row"
  div.innerHTML = `
    <input type="hidden" id="choice_body_${idx}" name="choices[${idx}][body_markdown]" value="" />
    <div class="prosemirror-wrapper">
      <div class="flex items-center gap-1 border-b border-gray-200 px-2 py-0.5">
        <button type="button" data-mark="bold" class="px-2 py-0.5 text-xs font-bold hover:bg-gray-100 rounded">B</button>
        <button type="button" data-mark="italic" class="px-2 py-0.5 text-xs italic hover:bg-gray-100 rounded">I</button>
        <button type="button" data-mark="underline" class="px-2 py-0.5 text-xs underline hover:bg-gray-100 rounded">U</button>
        <div class="ml-auto flex items-center gap-1.5">
          <label class="choice-correct-label flex items-center justify-center cursor-pointer transition-colors text-gray-300 hover:text-green-400" title="Korrekte Antwort">
            <input type="checkbox" name="choices[${idx}][is_correct]" value="true" class="sr-only" />
            <span class="hero-check-circle-solid h-5 w-5"></span>
          </label>
          <button type="button" onclick="window.removeQuestionChoice(this)"
            class="flex items-center justify-center text-gray-300 hover:text-red-400 transition-colors"
            title="Antwort entfernen">
            <span class="hero-trash h-4 w-4"></span>
          </button>
        </div>
      </div>
      <div data-prosemirror data-target="choice_body_${idx}" class="text-sm"></div>
    </div>
  `
  // Toggle correct styling on checkbox change
  const checkbox = div.querySelector("input[type=checkbox]")
  const label = div.querySelector(".choice-correct-label")
  checkbox.addEventListener("change", () => updateCorrectStyle(label, checkbox.checked))
  return div
}

function updateCorrectStyle(label, checked) {
  if (checked) {
    label.classList.remove("text-gray-300", "hover:text-green-400")
    label.classList.add("text-green-500")
  } else {
    label.classList.remove("text-green-500")
    label.classList.add("text-gray-300", "hover:text-green-400")
  }
}

function reindexChoices() {
  const container = document.getElementById("choices-container")
  Array.from(container.querySelectorAll(".choice-row")).forEach((row, idx) => {
    const checkbox = row.querySelector("input[type=checkbox]")
    if (checkbox) checkbox.name = `choices[${idx}][is_correct]`
    const hidden = row.querySelector("input[type=hidden]")
    if (hidden) { hidden.id = `choice_body_${idx}`; hidden.name = `choices[${idx}][body_markdown]` }
    const editor = row.querySelector("[data-prosemirror]")
    if (editor) editor.setAttribute("data-target", `choice_body_${idx}`)
  })
}

window.addQuestionChoice = function() {
  const container = document.getElementById("choices-container")
  const idx = container.querySelectorAll(".choice-row").length
  const div = buildChoiceRow(idx)
  container.appendChild(div)
  const editorEl = div.querySelector("[data-prosemirror]")
  window.initProseMirrorEditor(editorEl)
}

window.removeQuestionChoice = function(btn) {
  const row = btn.closest(".choice-row")
  if (row) row.remove()
  reindexChoices()
}

// Wire up correct-toggle styling for server-rendered rows
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".choice-row").forEach(row => {
    const checkbox = row.querySelector("input[type=checkbox]")
    const label = row.querySelector(".choice-correct-label")
    if (checkbox && label) {
      checkbox.addEventListener("change", () => updateCorrectStyle(label, checkbox.checked))
    }
  })
})
