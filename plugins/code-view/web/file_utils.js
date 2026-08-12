export function fileNameOf(path) {
  const index = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return index >= 0 ? path.slice(index + 1) : path;
}

export function directoryOf(path) {
  const index = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return index > 0 ? path.slice(0, index) : '';
}

export function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB'];
  let value = bytes;
  let unit = -1;
  do {
    value /= 1024;
    unit += 1;
  } while (value >= 1024 && unit < units.length - 1);
  return `${value < 10 ? value.toFixed(1) : value.toFixed(0)} ${units[unit]}`;
}

export function decodeText(buffer) {
  const bytes = new Uint8Array(buffer);
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
    return {
      text: new TextDecoder('utf-16le').decode(bytes.subarray(2)),
      encoding: 'UTF-16 LE',
    };
  }
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    const swapped = bytes.slice(2);
    for (let index = 0; index + 1 < swapped.length; index += 2) {
      [swapped[index], swapped[index + 1]] = [swapped[index + 1], swapped[index]];
    }
    return {
      text: new TextDecoder('utf-16le').decode(swapped),
      encoding: 'UTF-16 BE',
    };
  }
  const offset = bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf
    ? 3
    : 0;
  return {
    text: new TextDecoder('utf-8').decode(bytes.subarray(offset)),
    encoding: 'UTF-8',
  };
}
