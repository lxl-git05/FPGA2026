// Decode HDL captures using the FPGA Monitor's real codec and encoder.
// Run after DLB/scripts/test_pid_uart.ps1.
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
  for (let n = 0; n < bytes.length; n += 3) decoder.push(bytes.subarray(n, n + 3), frames.length * 20);
}
assert.equal(frames.length, lines.length);
assert.ok(frames.length >= 20);
assert.equal(frames[0].samples[10].value, 1049 / 65536);
for (const [seq, frame] of frames.entries()) {
  assert.equal(frame.seq, seq);
  assert.deepEqual(frame.samples.map(sample => sample.sourceId), [1, 2, 3, 4, 5, 6, 0x10, 0x11, 0x12, 0x20, 0x21, 0x22]);
  assert.deepEqual(frame.samples.map(sample => sample.type), [3, 1, 3, 1, 1, 3, 3, 3, 3, 3, 3, 3]);
  const [aGoal, aReal, aSet, pGoal, pReal, pSet] = frame.samples.map(sample => sample.value);
  assert.ok(aGoal >= 1960 && aGoal <= 2160);
  assert.ok(aReal >= 0 && aReal <= 4095);
  assert.ok(Math.abs(aSet) <= 100 && Math.abs(pSet) <= 100);
  assert.ok(Math.abs(pGoal) <= 4080);
  assert.ok(Number.isInteger(pReal));
  // Original PID integer outputs are encoded as Q16.16 only at the UART boundary.
  assert.ok(Number.isInteger(aGoal) && Number.isInteger(aSet) && Number.isInteger(pSet));
  assert.equal(aGoal, 2060 - pSet);
}
assert.ok(frames.some(frame => frame.samples[2].value < 0));
assert.ok(frames.some(frame => frame.samples[2].value > 0));
assert.ok(frames.some(frame => frame.samples[8].value === -0.5));
assert.ok(frames.some(frame => frame.samples[9].value === 0.25));
const commands = fs.readFileSync(new URL('commands.hex', capture), 'utf8').trim().split(/\r?\n/)
  .map(line => line.trim().split(/\s+/).map(hex => parseInt(hex, 16)));
const values = [1, 0.5, -0.5, 0.25, 655 / 65536, 2];
for (const [n, id] of [0x10, 0x11, 0x12, 0x20, 0x21, 0x22].entries()) {
  const encoder = new ProtocolEncoder(0x1234);
  assert.deepEqual([...encoder.setParam(id, 3, values[n]).bytes], commands[n]);
}
console.log(`PASS: ${frames.length} physical UART frames decoded by FPGA Monitor; 12 IDs/types, original integer cascade, signed outputs, six PC gain commands verified`);
