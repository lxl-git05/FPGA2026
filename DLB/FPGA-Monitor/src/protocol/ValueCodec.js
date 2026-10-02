/**
 * Responsibility: The only RAW bits / signed RAW / human-value conversion boundary.
 * Allowed dependencies: ProtocolConstants.
 * Forbidden responsibilities: UART, frame layout, DOM, chart, parameter names.
 * Public API: supported(), typeName(), limits(), encode(), decode(), rawNumber().
 * Architecture invariants: Unknown types preserve bits without guessing; encode rejects invalid values.
 */
import { TYPE, hexId } from './ProtocolConstants.js';
const formats = new Map([
  [TYPE.INT32, { name: 'INT32', scale: 1, min: -2147483648, max: 2147483647 }],
  [TYPE.UINT32, { name: 'UINT32', scale: 1, min: 0, max: 4294967295 }],
  [TYPE.Q16_16, { name: 'Q16.16', scale: 65536, min: -2147483648, max: 2147483647 }],
  [TYPE.Q8_24, { name: 'Q8.24', scale: 16777216, min: -2147483648, max: 2147483647 }],
]);
export const supported = type => formats.has(type);
export const typeName = type => formats.get(type)?.name ?? `Unsupported Type ${hexId(type)}`;
export function limits(type) {
  const f = formats.get(type);
  if (!f) throw new RangeError(typeName(type));
  return { min: f.min / f.scale, max: f.max / f.scale, resolution: 1 / f.scale };
}
export function rawNumber(type, bits) { return type === TYPE.UINT32 || !supported(type) ? bits >>> 0 : bits | 0; }
export function decode(type, bits) {
  return supported(type) ? rawNumber(type, bits) / formats.get(type).scale : null;
}
export function encode(type, value) {
  const f = formats.get(type);
  if (!f) throw new RangeError(typeName(type));
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new TypeError('请输入有限数值');
  if (value < f.min / f.scale || value > f.max / f.scale) throw new RangeError('数值超出数据类型范围');
  if (f.scale === 1 && !Number.isInteger(value)) throw new RangeError('整数类型不接受小数');
  const raw = Math.round(value * f.scale);
  if (raw < f.min || raw > f.max) throw new RangeError('量化后超出 32 bit 范围');
  return raw >>> 0;
}
