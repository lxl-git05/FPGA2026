import { describe, it, expect } from 'vitest';
import { ProtocolEncoder } from '../src/protocol/ProtocolEncoder.js';
import { crc16 } from '../src/protocol/CRC16.js';
describe('SET_PARAM', () => {
  it('checks every field against the specification', () => {
    const { bytes, rawBits } = new ProtocolEncoder(0x1234).setParam(0x10, 3, 0.25);
    expect([...bytes.slice(0, 14)]).toEqual([0xa5, 0x5a, 1, 0x10, 0x34, 0x12, 6, 0, 0x10, 3, 0, 0x40, 0, 0]);
    expect(bytes.length).toBe(16); expect(rawBits).toBe(16384);
    expect(new DataView(bytes.buffer).getUint16(14, true)).toBe(crc16(bytes.subarray(2, 14)));
  });
  it('wraps seq 65535 to 0', () => {
    const encoder = new ProtocolEncoder(65535); expect(encoder.setParam(2, 1, -1).seq).toBe(65535); expect(encoder.setParam(2, 1, -2).seq).toBe(0);
  });
  it('rejects invalid ID and value before advancing seq', () => {
    const encoder = new ProtocolEncoder(); expect(() => encoder.setParam(256, 3, 1)).toThrow(); expect(() => encoder.setParam(1, 3, NaN)).toThrow(); expect(encoder.seq).toBe(0);
  });
});
