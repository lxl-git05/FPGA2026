/**
 * Responsibility: CRC-16/MODBUS over the supplied bytes.
 * Allowed dependencies: None.
 * Forbidden responsibilities: Frame construction, value conversion, DOM.
 * Public API: crc16(bytes).
 * Architecture invariants: Initial FFFF, reflected polynomial A001.
 */
export function crc16(bytes) {
  let crc = 0xffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xa001 : 0);
  }
  return crc;
}
