use std::io::{self, Error, ErrorKind};

const MAX_TCR_OUTPUT_BYTES: usize = 256 * 1024 * 1024;
const MAGIC: &[u8] = b"!!8-Bit!!";

/// Decompresses a `.tcr` Psion e-book binary byte stream into plain text or HTML.
pub fn decompress_tcr(bytes: &[u8]) -> io::Result<String> {
    if bytes.len() < MAGIC.len() || &bytes[..MAGIC.len()] != MAGIC {
        return Err(Error::new(
            ErrorKind::InvalidData,
            "Invalid TCR header: missing '!!8-Bit!!' magic",
        ));
    }

    let mut offset = MAGIC.len();
    let mut dictionary: [Vec<u8>; 256] = std::array::from_fn(|_| Vec::new());

    for entry in dictionary.iter_mut() {
        if offset >= bytes.len() {
            return Err(Error::new(
                ErrorKind::UnexpectedEof,
                "Truncated TCR dictionary table",
            ));
        }
        let len = bytes[offset] as usize;
        offset += 1;
        if offset + len > bytes.len() {
            return Err(Error::new(
                ErrorKind::UnexpectedEof,
                "TCR dictionary entry length exceeds file bounds",
            ));
        }
        *entry = bytes[offset..offset + len].to_vec();
        offset += len;
    }

    let mut decoded = Vec::with_capacity(bytes.len() * 2);
    while offset < bytes.len() {
        let index = bytes[offset] as usize;
        offset += 1;
        let entry = &dictionary[index];
        if decoded.len() + entry.len() > MAX_TCR_OUTPUT_BYTES {
            return Err(Error::new(
                ErrorKind::InvalidData,
                "TCR decompressed size exceeds safety limit of 256 MiB",
            ));
        }
        decoded.extend_from_slice(entry);
    }

    let raw_text = decode_book_text(&decoded);
    if looks_like_html(&raw_text) {
        Ok(raw_text)
    } else {
        Ok(wrap_as_html(&raw_text))
    }
}

fn decode_book_text(data: &[u8]) -> String {
    match String::from_utf8(data.to_vec()) {
        Ok(utf8_str) => utf8_str,
        Err(_) => data.iter().map(|&b| b as char).collect(),
    }
}

fn looks_like_html(text: &str) -> bool {
    let trimmed = text.trim_start();
    trimmed.starts_with("<!doctype")
        || trimmed.starts_with("<!DOCTYPE")
        || trimmed.starts_with("<html")
        || trimmed.starts_with("<HTML")
        || trimmed.starts_with("<body")
        || trimmed.starts_with("<BODY")
        || trimmed.starts_with("<head")
        || trimmed.starts_with("<HEAD")
}

fn wrap_as_html(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len() + 128);
    for ch in text.chars() {
        match ch {
            '&' => escaped.push_str("&amp;"),
            '<' => escaped.push_str("&lt;"),
            '>' => escaped.push_str("&gt;"),
            '"' => escaped.push_str("&quot;"),
            '\'' => escaped.push_str("&#39;"),
            other => escaped.push(other),
        }
    }
    format!("<!doctype html><meta charset=\"utf-8\"><style>body{{font-family:sans-serif;line-height:1.6;padding:1.5rem;max-width:800px;margin:auto;}}pre{{white-space:pre-wrap;word-wrap:break-word;}}</style><pre>{escaped}</pre>")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decompress_simple_tcr() {
        let mut sample = Vec::new();
        sample.extend_from_slice(MAGIC);
        for index in 0..256 {
            if index == 42 {
                let s = b"Hello, TCR World!";
                sample.push(s.len() as u8);
                sample.extend_from_slice(s);
            } else {
                sample.push(0);
            }
        }
        sample.push(42);

        let result = decompress_tcr(&sample).unwrap();
        assert!(result.contains("Hello, TCR World!"));
        assert!(result.contains("<pre>"));
    }

    #[test]
    fn invalid_magic_fails() {
        let sample = b"Not-A-TCR-File";
        assert!(decompress_tcr(sample).is_err());
    }
}
