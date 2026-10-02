// Integration check against the FPGA Monitor's actual codec, not a second decoder.
// Run after the HDL test: node DLB/tests/check_pid_uart_codec.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { ProtocolDecoder } from '../FPGA-Monitor/src/protocol/ProtocolDecoder.js';
import { ProtocolEncoder } from '../FPGA-Monitor/src/protocol/ProtocolEncoder.js';
const capture = new URL('../../Claude_Temp/PID_UART_validation/telemetry.hex', import.meta.url);
const lines = fs.readFileSync(capture, 'utf8').trim().split(/\r?\n/);
const decoder = new ProtocolDecoder();
const frames = [];
decoder.on('telemetry', frame => frames.push(frame));
decoder.on('error', error => assert.fail(JSON.stringify(error)));
for (const line of lines) {
  const bytes = Uint8Array.from(line.trim().split(/\s+/), hex => parseInt(hex, 16));
  // UART reads are arbitrary; deliberately feed fragmented bytes.
  for (let n = 0; n < bytes.length; n += 3) decoder.push(bytes.subarray(n, n + 3), frames.length * 20);
}
assert.equal(frames.length, lines.length);
assert.ok(frames.length >= 7);
for (const [seq, frame] of frames.entries()) {
  assert.equal(frame.seq, seq);
  assert.deepEqual(frame.samples.map(sample => sample.sourceId), [1, 2, 3, 4, 0x10, 0x11, 0x12]);
  assert.deepEqual(frame.samples.map(sample => sample.type), [1, 1, 1, 1, 3, 3, 3]);
  const [goal, real, error, set] = frame.samples.map(sample => sample.value);
  assert.equal(error, Math.max(-2147483648, Math.min(2147483647, goal - real)));
  assert.ok(set >= -2500 && set <= 2500);
}
assert.ok(frames.some(frame => frame.samples[3].value === -2500));
assert.ok(frames.some(frame => frame.samples[3].value === 2500));
assert.ok(frames.some(frame => frame.samples[6].value === -0.5));
const encoder = new ProtocolEncoder(0x1234);
const command = encoder.setParam(0x10, 3, 1);
assert.equal(command.rawBits, 65536);
// Exactly the bytes driven into the DUT in write_param(Kp, Q16.16, 65536).
const commands = fs.readFileSync(new URL('commands.hex', capture), 'utf8').trim().split(/\r?\n/);
const firstCommand = commands[0].trim().split(/\s+/).map(hex => parseInt(hex, 16));
assert.deepEqual([...command.bytes], firstCommand);
console.log(`PASS: ${frames.length} captured physical UART frames decoded by FPGA Monitor; signed values, Q16.16, goal/real/set, PC command verified`);
