import { describe, it, expect } from 'vitest';
import { encode, decode, rawNumber, limits, supported, typeName } from '../src/protocol/ValueCodec.js';
describe('sole value conversion boundary', () => {
  it.each([[1, 1000, 1000], [1, -520, 0xfffffdf8], [1, -2147483648, 0x80000000], [1, 2147483647, 0x7fffffff],
    [2, 4294967295, 0xffffffff], [2, 0, 0], [3, 0, 0], [3, 0.25, 16384], [3, 0.2, 13107], [3, -1.5, 0xfffe8000],
    [4, 0.25, 4194304], [4, -1.5, 0xfe800000]])('encode type=%i value=%f', (type, value, bits) => {
    expect(encode(type, value)).toBe(bits);
    expect(Math.abs(decode(type, bits) - value)).toBeLessThanOrEqual(limits(type).resolution / 2);
  });
  it.each([[1, 2147483648], [1, -2147483649], [1, 0.1], [2, -1], [2, 4294967296], [2, 1.1],
    [3, 32768], [3, -32768.1], [4, 128], [4, -128.1], [3, NaN], [3, Infinity], [3, -Infinity], [3, '0.25']])('reject type=%i value=%s', (type, value) => expect(() => encode(type, value)).toThrow());
  it.each([1, 2, 3, 4])('accept exact type boundaries %i', type => {
    const range = limits(type); expect(decode(type, encode(type, range.min))).toBe(range.min); expect(decode(type, encode(type, range.max))).toBe(range.max);
  });
  it('unknown retains unsigned raw without conversion', () => {
    expect(supported(0x99)).toBe(false); expect(decode(0x99, 0xffffffff)).toBeNull(); expect(rawNumber(0x99, 0xffffffff)).toBe(4294967295);
    expect(typeName(0x99)).toBe('Unsupported Type 0x99'); expect(() => encode(0x99, 1)).toThrow();
  });
});
