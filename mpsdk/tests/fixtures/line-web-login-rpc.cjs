const str = value => { const bytes = Buffer.from(value); return [...uint(bytes.length), ...bytes]; };
function uint(value) { const bytes = []; do { bytes.push((value & 127) | (value > 127 ? 128 : 0)); value >>>= 7; } while (value); return bytes; }
function reply(source, method, sequence, result) {
  const fields = result.consentUrl ? [source === 'browser' ? 0x1c : 0x2c, 0x15, 8, 0x2b,
    result.sessionString ? 2 : 1, 0x88, ...str('consentUrl'), ...str(result.consentUrl),
    ...(result.sessionString ? [...str('sessionString'), ...str(result.sessionString)] : []), 0, 0] :
    [0x0c, 0, 0x18, ...str(result.returnUrl), 0, 0];
  return Uint8Array.from([0x82, 0x41, ...uint(sequence), ...str(method), ...fields]);
}
module.exports = { reply };
