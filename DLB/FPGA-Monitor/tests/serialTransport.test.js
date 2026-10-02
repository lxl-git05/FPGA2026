import { describe, it, expect, vi } from 'vitest';
import { SerialTransport } from '../src/serial/SerialTransport.js';
function setup() {
  let source; const writes = [];
  const port = {
    readable: new ReadableStream({ start(controller) { source = controller; } }),
    writable: new WritableStream({ async write(bytes) { writes.push([...bytes]); } }),
    open: vi.fn(async () => {}), close: vi.fn(async () => {}), getInfo: () => ({ usbVendorId: 0x1234, usbProductId: 0x5678 }),
  };
  return { transport: new SerialTransport({ requestPort: vi.fn(async () => port) }), port, writes, source };
}
describe('Web Serial lifecycle using real stream primitives', () => {
  it('115200 8N1, reads bytes, serializes writes and releases locks before close', async () => {
    const { transport, port, writes, source } = setup(); const received = [];
    transport.on('bytes', b => received.push([...b])); await transport.open(); expect(port.open).toHaveBeenCalledWith({ baudRate: 115200, dataBits: 8, stopBits: 1, parity: 'none', flowControl: 'none' });
    source.enqueue(new Uint8Array([0xa5])); await new Promise(resolve => setTimeout(resolve, 0)); expect(received).toEqual([[0xa5]]);
    await Promise.all([transport.write(new Uint8Array([1])), transport.write(new Uint8Array([2]))]); expect(writes).toEqual([[1], [2]]);
    await transport.close(); expect(port.readable.locked).toBe(false); expect(port.writable.locked).toBe(false); expect(port.close).toHaveBeenCalledTimes(1); expect(transport.connected).toBe(false);
    await expect(transport.write(new Uint8Array([3]))).rejects.toThrow();
  });
  it('disconnect read error closes port safely', async () => {
    const { transport, port, source } = setup(); const errors = []; transport.on('error', e => errors.push(e));
    await transport.open(); source.error(new Error('unplugged')); await new Promise(resolve => setTimeout(resolve, 10));
    expect(errors).toHaveLength(1); expect(transport.connected).toBe(false); expect(port.close).toHaveBeenCalledTimes(1);
  });
  it('unsupported browser and cancelled permission request reject safely', async () => {
    await expect(new SerialTransport(null).open()).rejects.toThrow('不支持');
    const transport = new SerialTransport({ requestPort: async () => { throw new DOMException('cancel', 'NotFoundError'); } });
    await expect(transport.open()).rejects.toMatchObject({ name: 'NotFoundError' }); expect(transport.connected).toBe(false);
  });
});
