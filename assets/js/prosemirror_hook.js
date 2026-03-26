import { EditorState } from "prosemirror-state"
import { EditorView } from "prosemirror-view"
import { Schema } from "prosemirror-model"
import { schema as basicSchema } from "prosemirror-schema-basic"
import { baseKeymap, toggleMark } from "prosemirror-commands"
import { keymap } from "prosemirror-keymap"

// Minimal schema: bold, italic, underline, paragraphs only
const markdownSchema = new Schema({
  nodes: basicSchema.spec.nodes,
  marks: {
    bold: {
      parseDOM: [{ tag: "strong" }, { tag: "b" }],
      toDOM() { return ["strong", 0] }
    },
    italic: {
      parseDOM: [{ tag: "em" }, { tag: "i" }],
      toDOM() { return ["em", 0] }
    },
    underline: {
      parseDOM: [{ tag: "u" }],
      toDOM() { return ["u", 0] }
    }
  }
})

// Serialize ProseMirror doc to Markdown
function toMarkdown(doc) {
  const parts = []

  doc.forEach(node => {
    if (node.type.name === "paragraph") {
      parts.push(serializeInline(node))
    }
  })

  return parts.join("\n\n")
}

function serializeInline(node) {
  let result = ""
  node.forEach(child => {
    if (child.type.name === "text") {
      let text = child.text
      const hasBold = child.marks.some(m => m.type.name === "bold")
      const hasItalic = child.marks.some(m => m.type.name === "italic")
      const hasUnderline = child.marks.some(m => m.type.name === "underline")

      if (hasBold) text = `**${text}**`
      if (hasItalic) text = `*${text}*`
      if (hasUnderline) text = `<u>${text}</u>`

      result += text
    }
  })
  return result
}

// Parse Markdown to ProseMirror doc
function fromMarkdown(markdown, schema) {
  if (!markdown || markdown.trim() === "") {
    return schema.node("doc", null, [schema.node("paragraph")])
  }

  const paragraphs = markdown.split(/\n\n+/)

  const nodes = paragraphs.map(para => {
    const inline = parseInline(para.trim(), schema)
    return schema.node("paragraph", null, inline.length > 0 ? inline : [schema.text(" ")])
  })

  return schema.node("doc", null, nodes)
}

function parseInline(text, schema) {
  const nodes = []
  const regex = /(\*\*(.+?)\*\*|\*(.+?)\*|<u>(.+?)<\/u>|([^*<]+))/gs
  let match

  while ((match = regex.exec(text)) !== null) {
    if (match[2]) {
      nodes.push(schema.text(match[2], [schema.marks.bold.create()]))
    } else if (match[3]) {
      nodes.push(schema.text(match[3], [schema.marks.italic.create()]))
    } else if (match[4]) {
      nodes.push(schema.text(match[4], [schema.marks.underline.create()]))
    } else if (match[5]) {
      nodes.push(schema.text(match[5]))
    }
  }

  return nodes
}

export function initEditor(el) {
  const targetId = el.dataset.target
  const hiddenInput = document.getElementById(targetId)
  const initialMarkdown = hiddenInput ? hiddenInput.value : ""

  const doc = fromMarkdown(initialMarkdown, markdownSchema)

  const state = EditorState.create({
    doc,
    plugins: [
      keymap({
        "Mod-b": toggleMark(markdownSchema.marks.bold),
        "Mod-i": toggleMark(markdownSchema.marks.italic),
        "Mod-u": toggleMark(markdownSchema.marks.underline),
        ...baseKeymap
      })
    ]
  })

  const view = new EditorView(el, {
    state,
    dispatchTransaction(transaction) {
      const newState = view.state.apply(transaction)
      view.updateState(newState)

      if (hiddenInput && transaction.docChanged) {
        hiddenInput.value = toMarkdown(newState.doc)
      }
    }
  })

  // Toolbar button handlers within the same .prosemirror-wrapper
  const wrapper = el.closest(".prosemirror-wrapper")
  if (wrapper) {
    wrapper.querySelectorAll("[data-mark]").forEach(btn => {
      btn.addEventListener("mousedown", e => {
        e.preventDefault()
        const markName = btn.dataset.mark
        const mark = markdownSchema.marks[markName]
        if (mark) {
          toggleMark(mark)(view.state, view.dispatch)
          view.focus()
        }
      })
    })
  }

  return view
}

// LiveView hook (for LiveView pages)
const ProseMirrorHook = {
  mounted() {
    this._view = initEditor(this.el)
  },
  destroyed() {
    if (this._view) this._view.destroy()
  }
}

export default ProseMirrorHook
