/**
 * Responsibility: Bounded incremental stream framing, validation, recovery and Telemetry decoding.
 * Allowed dependencies: Events, Constants, CRC16, ValueCodec.
 * Forbidden responsibilities: DOM, ECharts, SerialPort, persistence.
 * Public API: push(bytes, hostReceiveTime), reset(), telemetry/frame/error events.
 * Architecture invariants: Read boundaries are irrelevant; corrupt frames never produce samples.
 */
import { Events } from '../core/Events.js';
import { VERSION, MSG, MAX_PAYLOAD } from './ProtocolConstants.js';
import { crc16 } from './CRC16.js';
import { decode, rawNumber } from './ValueCodec.js';
export class ProtocolDecoder extends Events {
  buffer = [];
  reset() { this.buffer = []; }
  push(bytes, hostReceiveTime = performance.now()) {
    // Process incrementally even for an enormous read: retained state is at most one frame.
    for (const byte of bytes) {
      this.buffer.push(byte);
      this.drain(hostReceiveTime);
    }
  }
  fail(kind, detail, bytes = this.buffer) {
    this.emit('error', { kind, detail, bytes: Uint8Array.from(bytes) });
    this.buffer.shift();
  }
  drain(hostReceiveTime) {
    while (this.buffer.length) {
      if (this.buffer[0] !== 0xa5) { this.buffer.shift(); continue; }
      if (this.buffer.length < 2) return;
      if (this.buffer[1] !== 0x5a) { this.buffer.shift(); continue; }
      if (this.buffer.length < 8) return;
      const len = this.buffer[6] | (this.buffer[7] << 8);
      if (this.buffer[2] !== VERSION) { this.fail('FORMAT', 'Unsupported protocol version'); continue; }
      if (len > MAX_PAYLOAD || (this.buffer[3] === MSG.TELEMETRY && (len < 1 || (len - 1) % 6 !== 0))) {
        this.fail('FORMAT', `Invalid LEN=${len}`); continue;
      }
      // COUNT can reject a plausible but corrupt LEN before waiting for its claimed payload.
      if (this.buffer[3] === MSG.TELEMETRY && this.buffer.length >= 9 && len !== 1 + this.buffer[8] * 6) {
        this.fail('FORMAT', 'COUNT / LEN mismatch'); continue;
      }
      if (this.buffer.length < len + 10) return;
      const bytes = Uint8Array.from(this.buffer.slice(0, len + 10));
      const view = new DataView(bytes.buffer);
      const expected = crc16(bytes.subarray(2, -2));
      const received = view.getUint16(bytes.length - 2, true);
      if (expected !== received) {
        this.fail('CRC', `Expected=${expected.toString(16)} Received=${received.toString(16)}`, bytes); continue;
      }
      this.buffer.splice(0, bytes.length);
      const frame = { bytes, seq: view.getUint16(4, true), type: bytes[3], hostReceiveTime };
      this.emit('frame', frame);
      if (frame.type !== MSG.TELEMETRY) continue;
      const samples = [];
      for (let i = 0; i < bytes[8]; i++) {
        const offset = 9 + i * 6;
        const type = bytes[offset + 1];
        const rawBits = view.getUint32(offset + 2, true);
        samples.push({ sourceId: bytes[offset], type, rawBits, rawValue: rawNumber(type, rawBits), value: decode(type, rawBits) });
      }
      this.emit('telemetry', { ...frame, samples });
    }
  }
}
