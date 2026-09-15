// Reader page for documents foliate-js has no parser for.
//
// The Rust host decompresses a `.tcr` file into HTML and serves it as
// `/file/<name>.html`; foliate-js ships its own reader UI for the formats it
// does parse (`reader.html`), so this page only has to read `?url=`, turn the
// document into a book and drive the paginator that comes with the library.

import '/view.js'
import { makeHTMLBook } from './html-book.js'

const view = document.querySelector('#view')
const titleElement = document.querySelector('#title')
const locationElement = document.querySelector('#location')
const progressElement = document.querySelector('#progress')
const messageElement = document.querySelector('#message')

const showError = error => {
    console.error(error)
    messageElement.textContent = String(error?.message ?? error)
    messageElement.hidden = false
    view.hidden = true
    document.querySelector('.progress').hidden = true
    progressElement.disabled = true
}

const onKeyDown = event => {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    switch (event.key) {
        case 'ArrowLeft':
        case 'PageUp':
        case 'h':
            view.goLeft()
            break
        case 'ArrowRight':
        case 'PageDown':
        case ' ':
        case 'l':
            view.goRight()
            break
        case 'Home':
            view.goToFraction(0)
            break
        case 'End':
            view.goToFraction(1)
            break
        default:
            return
    }
    event.preventDefault()
}

const onRelocate = ({ detail }) => {
    const { fraction } = detail ?? {}
    if (typeof fraction !== 'number' || !Number.isFinite(fraction)) return
    progressElement.value = String(fraction)
    locationElement.textContent = `${Math.round(fraction * 100)}%`
}

const open = async url => {
    const response = await fetch(url)
    if (!response.ok) throw new Error(
        `Failed to load the document (${response.status} ${response.statusText}).`)
    // foliate-js names a fetched book after the URL path; the paginator only
    // needs the file name to fall back to when the document has no title.
    const name = new URL(response.url).pathname.split('/').pop() ?? ''
    const book = await makeHTMLBook(new File([await response.blob()], name))

    titleElement.textContent = book.metadata.title
    document.title = book.metadata.title

    view.addEventListener('relocate', onRelocate)
    // The focused document is the section iframe, so it needs the shortcuts
    // as well as this page.
    view.addEventListener('load', ({ detail: { doc } }) =>
        doc.addEventListener('keydown', onKeyDown))
    progressElement.addEventListener('input', ({ target }) =>
        view.goToFraction(parseFloat(target.value)))

    await view.open(book)
    await view.goToTextStart()
}

document.querySelector('#previous').addEventListener('click', () => view.goLeft())
document.querySelector('#next').addEventListener('click', () => view.goRight())

const url = new URLSearchParams(location.search).get('url')
if (url) open(url).catch(showError)
else showError(new Error('No document was provided.'))
