// Book adapter for documents foliate-js has no parser for.
//
// The Rust host decompresses a `.tcr` file into HTML (`src/tcr.rs`) and serves
// it as `/file/<name>.html`. foliate-js picks a parser from the book itself and
// none of its parsers reads HTML, so this module exposes one such document as a
// book the bundled paginator can lay out like any other reflowable book.

/// Markup characters per section. A whole novel in one section would be laid
/// out in a single pass and stall the paginator; the limit is only a ceiling,
/// sections still end on element boundaries.
const SECTION_LIMIT = 64 * 1024

/// Baseline styling for every section document. The paginator adds the layout
/// rules; these only keep running text comfortable.
const STYLES = `
:root { color-scheme: light dark; }
body { line-height: 1.5; }
p { margin: .5em 0; }
h1, h2, h3, h4, h5, h6 { line-height: 1.3; }
img, svg, table { max-width: 100%; }
pre { white-space: pre-wrap; overflow-wrap: break-word; }
blockquote { margin: 1em 1.5em; }
a:link { color: #0b62c4; }
@media (prefers-color-scheme: dark) {
    a:link { color: lightblue; }
}
`

/// Elements that could run script, navigate away, or reach the network. Section
/// documents are rendered in an iframe that shares this page's origin, so
/// markup that arrives inside a book must not be able to act on its own.
const DROPPED = 'script, iframe, frame, frameset, object, embed, base, form, meta[http-equiv]'

/// Attributes whose value must not be a `javascript:` URL.
const URL_ATTRIBUTES = new Set(['href', 'src', 'xlink:href', 'action'])

const NEUTRALISED = /&/g
const LT = /</g
const GT = />/g

const escapeText = text => text
    .replace(NEUTRALISED, '&amp;')
    .replace(LT, '&lt;')
    .replace(GT, '&gt;')

const dropDangerous = doc => {
    for (const el of doc.querySelectorAll(DROPPED)) el.remove()
    for (const el of doc.querySelectorAll('*'))
        for (const { name, value } of Array.from(el.attributes)) {
            const attribute = name.toLowerCase()
            if (attribute.startsWith('on')) el.removeAttribute(name)
            else if (URL_ATTRIBUTES.has(attribute)
                && value.trim().toLowerCase().startsWith('javascript:'))
                el.removeAttribute(name)
        }
}

/// Splits `text` at line boundaries into pieces of at most [`SECTION_LIMIT`],
/// each serialized inside `shell`, so one oversized block is never laid out in
/// a single pass. `shell` must be empty and keeps its own name and attributes,
/// which is what preserves the styling of the text it wraps.
const splitText = (text, shell) => {
    const chunks = []
    let current = ''
    for (const line of text.split('\n')) {
        if (current && current.length + line.length > SECTION_LIMIT) {
            chunks.push(current)
            current = ''
        }
        current += `${line}\n`
    }
    if (current) chunks.push(current)
    return chunks.map(chunk => {
        shell.textContent = chunk
        return shell.outerHTML
    })
}

/// Markup of `body`, cut into section-sized pieces.
const splitBody = body => {
    const sections = []
    let current = ''
    const flush = () => {
        if (current) sections.push(current)
        current = ''
    }
    for (const node of body.childNodes) {
        if (node.nodeType === Node.ELEMENT_NODE) {
            if (node.outerHTML.length > SECTION_LIMIT) {
                flush()
                sections.push(...splitText(node.textContent, node.cloneNode(false)))
            } else {
                if (current.length + node.outerHTML.length > SECTION_LIMIT) flush()
                current += node.outerHTML
            }
        } else {
            const text = escapeText(node.textContent ?? '')
            if (!text.trim()) continue
            if (text.length > SECTION_LIMIT) {
                flush()
                // Plain text keeps its line breaks only inside `<pre>`.
                sections.push(...splitText(node.textContent, document.createElement('pre')))
            } else {
                if (current.length + text.length > SECTION_LIMIT) flush()
                current += text
            }
        }
    }
    flush()
    return sections
}

/// Title to show when the document brings none of its own. foliate-js names a
/// fetched book after the URL path, which is percent-encoded, so the file name
/// has to be decoded before it can be used.
const titleFromName = name => {
    const base = name.split('/').pop() ?? ''
    let decoded = base
    try {
        decoded = decodeURIComponent(base)
    } catch {
        // A stray `%` is not an escape sequence; keep the raw name.
    }
    return decoded.replace(/\.[^.]*$/, '') || decoded || 'Document'
}

/// Reads an HTML document and returns it as a foliate book.
export const makeHTMLBook = async file => {
    const text = await file.text()
    const doc = new DOMParser().parseFromString(text, 'text/html')
    const title = doc.title.trim() || titleFromName(file.name)
    // Section documents are rebuilt from the body, so styling the book brings
    // in its head has to travel with it.
    const authorStyles = Array.from(doc.head?.querySelectorAll('style') ?? [],
        el => el.outerHTML).join('')

    dropDangerous(doc)
    const sections = splitBody(doc.body ?? doc.documentElement)
    if (!sections.length) throw new Error('The document contains no readable text')

    const styles = URL.createObjectURL(new Blob([STYLES], { type: 'text/css' }))
    const pages = new Map()
    const urls = new Set([styles])

    const load = index => {
        if (pages.has(index)) return pages.get(index)
        const html = '<!DOCTYPE html><html><head><meta charset="utf-8">'
            + `<link rel="stylesheet" href="${styles}"></head>`
            + `<body>${authorStyles}${sections[index]}</body></html>`
        const url = URL.createObjectURL(new Blob([html], { type: 'text/html' }))
        pages.set(index, url)
        urls.add(url)
        return url
    }
    const unload = index => {
        const url = pages.get(index)
        if (!url) return
        URL.revokeObjectURL(url)
        urls.delete(url)
        pages.delete(index)
    }

    const book = {}
    book.metadata = { title }
    book.sections = sections.map((html, index) => ({
        id: index,
        load: () => load(index),
        unload: () => unload(index),
        // Reading progress is weighted by section size.
        size: html.length,
    }))
    book.toc = []
    // The reader only needs these to have progress and location tracking; a
    // decompressed `.tcr` file has no table of contents and rarely links on.
    book.splitTOCHref = href => [Number(href), null]
    book.getTOCFragment = doc => doc.documentElement
    book.resolveHref = href => ({
        index: book.sections.findIndex(section => section.id === Number(href)),
    })
    book.isExternal = uri => /^\w+:/i.test(uri)
    book.destroy = () => {
        for (const url of urls) URL.revokeObjectURL(url)
        urls.clear()
        pages.clear()
    }
    return book
}
