import test from 'node:test';
import assert from 'node:assert/strict';

import {decodeText, directoryOf, fileNameOf, formatBytes} from './file_utils.js';

test('Windows path helpers split file name and directory', () => {
  const path = String.raw`C:\work\src\main.rs`;
  assert.equal(fileNameOf(path), 'main.rs');
  assert.equal(directoryOf(path), String.raw`C:\work\src`);
});

test('formatBytes uses compact binary units', () => {
  assert.equal(formatBytes(512), '512 B');
  assert.equal(formatBytes(1536), '1.5 KB');
  assert.equal(formatBytes(2 * 1024 * 1024), '2.0 MB');
});

test('decodeText recognizes UTF-8 BOM and UTF-16 LE', () => {
  const utf8 = Uint8Array.from([0xef, 0xbb, 0xbf, 0x6f, 0x6b]);
  assert.deepEqual(decodeText(utf8.buffer), {text: 'ok', encoding: 'UTF-8'});

  const utf16 = Uint8Array.from([0xff, 0xfe, 0x6f, 0x00, 0x6b, 0x00]);
  assert.deepEqual(decodeText(utf16.buffer), {text: 'ok', encoding: 'UTF-16 LE'});
});
