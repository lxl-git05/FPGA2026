import { describe, it, expect } from 'vitest';
import { crc16 } from '../src/protocol/CRC16.js';
describe('CRC-16/MODBUS reference vectors', () => {
  it('standard ASCII check vector', () => expect(crc16(new TextEncoder().encode('123456789'))).toBe(0x4b37));
  it('empty input keeps initial FFFF', () => expect(crc16([])).toBe(0xffff));
  it('known Modbus request', () => expect(crc16([1, 3, 0, 0, 0, 10])).toBe(0xcdc5));
});
