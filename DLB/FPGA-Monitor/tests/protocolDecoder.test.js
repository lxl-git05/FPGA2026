import { describe, it, expect } from 'vitest';
import { ProtocolDecoder } from '../src/protocol/ProtocolDecoder.js';
import { makeTelemetry, makeFrame } from '../src/protocol/ProtocolEncoder.js';
const frame = seq => makeTelemetry(seq, [{ sourceId: 1, type: 1, value: -520 }, { sourceId: 0x10, type: 3, value: 0.25 }]);
const concat = (...bytes) => Uint8Array.from(bytes.flatMap(b => [...b]));
function setup() {
  const decoder = new ProtocolDecoder(); const output = [], errors = [], frames = [];
  decoder.on('telemetry', f => output.push(f)); decoder.on('error', e => errors.push(e)); decoder.on('frame', f => frames.push(f));
  return { decoder, output, errors, frames };
}
describe('incremental decoder', () => {
  it('complete mixed signed and Q frame', () => {
    const { decoder, output } = setup(); decoder.push(frame(42), 123.45);
    expect(output[0].seq).toBe(42); expect(output[0].hostReceiveTime).toBe(123.45);
    expect(output[0].samples.map(s => [s.rawValue, s.value])).toEqual([[-520, -520], [16384, 0.25]]);
  });
  it('one byte at a time with split header', () => {
    const { decoder, output } = setup(); for (const b of frame(42)) decoder.push([b]); expect(output).toHaveLength(1);
  });
  it('every possible two-chunk cut', () => {
    const bytes = frame(5);
    for (let i = 1; i < bytes.length; i++) { const { decoder, output } = setup(); decoder.push(bytes.slice(0, i)); expect(output).toHaveLength(0); decoder.push(bytes.slice(i)); expect(output).toHaveLength(1); }
  });
  it('deterministic pseudorandom chunks across 100 frames', () => {
    const { decoder, output } = setup(); const bytes = concat(...Array.from({ length: 100 }, (_, i) => frame(i)));
    let seed = 17;
    for (let i = 0; i < bytes.length;) { seed = (seed * 1664525 + 1013904223) >>> 0; const size = 1 + seed % 73; decoder.push(bytes.slice(i, i + size)); i += size; }
    expect(output.map(f => f.seq)).toEqual(Array.from({ length: 100 }, (_, i) => i)); expect(decoder.buffer.length).toBe(0);
  });
  it.each([[0, 8, 255, 0xa5], [0xa5]])('garbage and A5 A5 5A resync %s', (...garbage) => {
    const { decoder, output } = setup(); decoder.push(concat(garbage, frame(1), frame(2))); expect(output.map(f => f.seq)).toEqual([1, 2]);
  });
  it('partial frame waits then consumes two consecutive frames', () => {
    const { decoder, output } = setup(); const bytes = frame(7); decoder.push(bytes.slice(0, -1)); expect(output).toHaveLength(0);
    decoder.push(concat(bytes.slice(-1), frame(8))); expect(output.map(f => f.seq)).toEqual([7, 8]);
  });
  it('bad CRC rejected, following frame recovered', () => {
    const { decoder, output, errors } = setup(); const bad = frame(3); bad[bad.length - 1] ^= 0x80;
    decoder.push(concat(bad, frame(4))); expect(output.map(f => f.seq)).toEqual([4]); expect(errors[0].kind).toBe('CRC'); expect(errors[0].detail).toContain('Expected=');
  });
  it.each([
    [0xa5, 0x5a, 2, 1, 0, 0, 7, 0], [0xa5, 0x5a, 1, 1, 0, 0, 255, 255],
    [0xa5, 0x5a, 1, 1, 0, 0, 0, 0], [0xa5, 0x5a, 1, 1, 0, 0, 13, 0, 1],
  ])('invalid version or length recovers %s', (...bad) => {
    const { decoder, output, errors } = setup(); decoder.push(concat(bad, frame(9))); expect(output).toHaveLength(1); expect(errors[0].kind).toBe('FORMAT');
  });
  it('unknown message safely ignored and unknown TYPE preserved', () => {
    const { decoder, output, frames } = setup(); decoder.push(concat(makeFrame(0x55, 2, new Uint8Array()), makeTelemetry(3, [{ sourceId: 0xee, type: 0x99, rawBits: 0xf1234567 }])));
    expect(frames).toHaveLength(2); expect(output).toHaveLength(1); expect(output[0].samples[0]).toMatchObject({ sourceId: 0xee, type: 0x99, rawBits: 0xf1234567, value: null });
  });
  it('large noise remains bounded and max COUNT=255 accepted', () => {
    const { decoder, output } = setup(); decoder.push(new Uint8Array(100000).fill(0xa5)); expect(decoder.buffer.length).toBe(1);
    decoder.push(makeTelemetry(5, Array.from({ length: 255 }, (_, sourceId) => ({ sourceId, type: 2, value: 4294967295 }))));
    expect(output[0].samples).toHaveLength(255); expect(decoder.buffer.length).toBe(0);
  });
});
