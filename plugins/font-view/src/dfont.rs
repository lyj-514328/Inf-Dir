//! DFONT container handling.
//!
//! A DFONT is a Mac resource fork wrapping a single sfnt font stream, which the
//! Windows font engine cannot load directly. Extract the `sfnt` resource and
//! hand the plain TTF over to `@font-face`.

use std::fs;
use std::io::Write;
use std::path::Path;

pub fn extract_dfont(source: &Path, output: &Path) -> Result<(), String> {
    let file = fs::read(source).map_err(|error| format!("failed to read DFONT: {error}"))?;
    if file.len() < 16 {
        return Err("DFONT resource fork header is incomplete.".to_owned());
    }

    let data_offset = read_offset(&file, 0)?;
    let map_offset = read_offset(&file, 4)?;
    let data_length = read_length(&file, 8)?;
    let map_length = read_length(&file, 12)?;
    check_range(&file, data_offset, data_length, "DFONT data section")?;
    check_range(&file, map_offset, map_length, "DFONT resource map")?;

    let type_list = map_offset + read_u16(&file, map_offset + 24)? as usize;
    check_range(&file, type_list, 2, "DFONT type list")?;
    let type_count = read_u16(&file, type_list)? as usize + 1;
    let entries = type_list + 2;
    check_range(&file, entries, type_count * 8, "DFONT type entries")?;

    for type_index in 0..type_count {
        let type_entry = entries + type_index * 8;
        let kind = &file[type_entry..type_entry + 4];
        if kind != b"sfnt" {
            continue;
        }

        let resource_count = read_u16(&file, type_entry + 4)? as usize + 1;
        let references = type_list + read_u16(&file, type_entry + 6)? as usize;
        check_range(&file, references, resource_count * 12, "DFONT sfnt references")?;
        let relative_data_offset = read_int24(&file, references + 5)?;
        let resource = data_offset + relative_data_offset as usize;
        let length = read_length(&file, resource)?;
        check_range(&file, resource + 4, length, "DFONT sfnt resource")?;

        let mut out = fs::File::create(output)
            .map_err(|error| format!("failed to create extracted font: {error}"))?;
        out.write_all(&file[resource + 4..resource + 4 + length])
            .map_err(|error| format!("failed to write extracted font: {error}"))?;
        return Ok(());
    }

    Err("DFONT does not contain an sfnt font resource.".to_owned())
}

fn read_offset(file: &[u8], offset: usize) -> Result<usize, String> {
    let value = read_u32(file, offset)?;
    usize::try_from(value).map_err(|_| "DFONT offset is too large.".to_owned())
}

fn read_length(file: &[u8], offset: usize) -> Result<usize, String> {
    let value = read_u32(file, offset)?;
    usize::try_from(value).map_err(|_| "DFONT section is too large.".to_owned())
}

fn read_u16(file: &[u8], offset: usize) -> Result<u16, String> {
    check_range(file, offset, 2, "DFONT integer")?;
    Ok(u16::from_be_bytes([file[offset], file[offset + 1]]))
}

fn read_u32(file: &[u8], offset: usize) -> Result<u32, String> {
    check_range(file, offset, 4, "DFONT integer")?;
    Ok(u32::from_be_bytes([
        file[offset],
        file[offset + 1],
        file[offset + 2],
        file[offset + 3],
    ]))
}

fn read_int24(file: &[u8], offset: usize) -> Result<u32, String> {
    check_range(file, offset, 3, "DFONT resource offset")?;
    Ok((file[offset] as u32) << 16 | (file[offset + 1] as u32) << 8 | file[offset + 2] as u32)
}

fn check_range(file: &[u8], offset: usize, length: usize, field: &str) -> Result<(), String> {
    if offset > file.len() || length > file.len() - offset {
        return Err(format!("{field} is outside the file."));
    }
    Ok(())
}

#[cfg(test)]
pub fn build_test_dfont(payload: &[u8]) -> Vec<u8> {
    const DATA_OFFSET: usize = 256;
    let data_length = payload.len() + 4;
    let map_offset = (DATA_OFFSET + data_length + 3) & !3;
    let map_length = 50usize;
    let mut file = vec![0u8; map_offset + map_length];
    write_u32(&mut file, 0, DATA_OFFSET as u32);
    write_u32(&mut file, 4, map_offset as u32);
    write_u32(&mut file, 8, data_length as u32);
    write_u32(&mut file, 12, map_length as u32);
    file.copy_within(0..16, map_offset);
    write_u32(&mut file, DATA_OFFSET, payload.len() as u32);
    file[DATA_OFFSET + 4..DATA_OFFSET + 4 + payload.len()].copy_from_slice(payload);

    write_u16(&mut file, map_offset + 24, 28);
    write_u16(&mut file, map_offset + 26, map_length as u16);
    let type_list = map_offset + 28;
    write_u16(&mut file, type_list, 0);
    file[type_list + 2..type_list + 6].copy_from_slice(b"sfnt");
    write_u16(&mut file, type_list + 6, 0);
    write_u16(&mut file, type_list + 8, 10);
    let reference = type_list + 10;
    write_u16(&mut file, reference, 128);
    write_u16(&mut file, reference + 2, u16::MAX);
    file
}

#[cfg(test)]
fn write_u16(file: &mut [u8], offset: usize, value: u16) {
    file[offset..offset + 2].copy_from_slice(&value.to_be_bytes());
}

#[cfg(test)]
fn write_u32(file: &mut [u8], offset: usize, value: u32) {
    file[offset..offset + 4].copy_from_slice(&value.to_be_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dfont_self_test_roundtrip() {
        let payload = b"\0\x01\0\0Inf-Dir-font-test";
        let temp = std::env::temp_dir().join(format!(
            "inf-dir-dfont-test-{}",
            std::process::id()
        ));
        fs::create_dir_all(&temp).unwrap();
        let dfont = temp.join("test.dfont");
        let sfnt = temp.join("test.ttf");
        fs::write(&dfont, build_test_dfont(payload)).unwrap();
        extract_dfont(&dfont, &sfnt).unwrap();
        assert_eq!(fs::read(&sfnt).unwrap(), payload);
        fs::remove_dir_all(&temp).unwrap();
    }

    #[test]
    fn rejects_truncated_containers() {
        let temp = std::env::temp_dir().join(format!(
            "inf-dir-dfont-bad-{}",
            std::process::id()
        ));
        fs::create_dir_all(&temp).unwrap();
        let dfont = temp.join("bad.dfont");
        let out = temp.join("out.ttf");
        fs::write(&dfont, b"tiny").unwrap();
        assert!(extract_dfont(&dfont, &out).is_err());
        let full = build_test_dfont(b"abc");
        fs::write(&dfont, &full[..full.len() - 20]).unwrap();
        assert!(extract_dfont(&dfont, &out).is_err());
        fs::remove_dir_all(&temp).unwrap();
    }
}
