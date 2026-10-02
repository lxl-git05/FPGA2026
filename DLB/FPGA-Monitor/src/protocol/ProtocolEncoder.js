/**
 * Responsibility: Encode SET_PARAM with a wrapping TX sequence; frame helper for the mock.
 * Allowed dependencies: Constants, CRC16, ValueCodec.
 * Forbidden responsibilities: DOM, SerialPort, business identities.
 * Public API: ProtocolEncoder.setParam(), makeFrame(), makeTelemetry().
 * Architecture invariants: All application SET_PARAM bytes pass here; all multibyte fields are LE.
 */
import { VERSION, MSG, MAX_PAYLOAD } from './ProtocolConstants.js';
import { crc16 } from './CRC16.js';
import { encode } from './ValueCodec.js';
export function makeFrame(type, seq, payload) {
  if (payload.length > MAX_PAYLOAD) throw new RangeError('Payload too large');
  const frame = new Uint8Array(10 + payload.length);
  const view = new DataView(frame.buffer);
  frame.set([0xa5, 0x5a, VERSION, type]);
  view.setUint16(4, seq, true);
  view.setUint16(6, payload.length, true);
  frame.set(payload, 8);
  view.setUint16(frame.length - 2, crc16(frame.subarray(2, -2)), true);
  return frame;
}
export function makeTelemetry(seq, samples) {
  if (samples.length > 255) throw new RangeError('Maximum 255 parameters');
  const payload = new Uint8Array(1 + samples.length * 6);
  const view = new DataView(payload.buffer);
  payload[0] = samples.length;
  samples.forEach((s, i) => {
    payload[1 + i * 6] = s.sourceId;
    payload[2 + i * 6] = s.type;
    view.setUint32(3 + i * 6, s.rawBits ?? encode(s.type, s.value), true);
  });
  return makeFrame(MSG.TELEMETRY, seq, payload);
}
export class ProtocolEncoder {
  constructor(seq = 0) { this.seq = seq & 0xffff; }
  setParam(sourceId, type, value) {
    if (!Number.isInteger(sourceId) || sourceId < 0 || sourceId > 255) throw new RangeError('Invalid PARAM_ID');
    const rawBits = encode(type, value);
    const payload = new Uint8Array(6);
    payload.set([sourceId, type]);
    new DataView(payload.buffer).setUint32(2, rawBits, true);
    const bytes = makeFrame(MSG.SET_PARAM, this.seq, payload);
    const result = { bytes, seq: this.seq, rawBits };
    this.seq = (this.seq + 1) & 0xffff;
    return result;
  }
}
