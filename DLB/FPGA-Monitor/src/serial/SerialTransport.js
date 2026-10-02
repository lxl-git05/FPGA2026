/**
 * Responsibility: Web Serial byte I/O, connection lifecycle and serialized writes.
 * Allowed dependencies: Events and injected browser serial API.
 * Forbidden responsibilities: Protocol parsing, channel state, Q formats, DOM, ECharts.
 * Public API: open(), close(), write(); bytes/state/error events; connected, portLabel.
 * Architecture invariants: This is the only real SerialPort owner; release locks before close.
 */
import { Events } from '../core/Events.js';
export class SerialTransport extends Events {
  constructor(serial = globalThis.navigator?.serial) {
    super(); this.serial = serial; this.connected = false; this.portLabel = '—'; this.queue = Promise.resolve();
  }
  async open({ baudRate = 115200 } = {}) {
    if (!this.serial) throw new Error('此浏览器不支持 Web Serial，请使用 localhost / HTTPS 上的 Edge 或 Chrome');
    if (this.port || this.closing) throw new Error('Serial lifecycle busy');
    const port = await this.serial.requestPort();
    try { await port.open({ baudRate, dataBits: 8, stopBits: 1, parity: 'none', flowControl: 'none' }); }
    catch (error) { this.emit('state', 'Disconnected'); throw error; }
    this.port = port;
    const info = port.getInfo();
    this.portLabel = info.usbVendorId ? `USB ${info.usbVendorId.toString(16)}:${info.usbProductId?.toString(16) ?? '?'}` : 'Serial port';
    this.connected = true; this.emit('state', 'Connected');
    this.readTask = this.readLoop();
  }
  async readLoop() {
    try {
      while (this.connected && this.port?.readable) {
        this.reader = this.port.readable.getReader();
        try {
          while (this.connected) {
            const { value, done } = await this.reader.read();
            if (done) { this.connected = false; break; }
            if (value) this.emit('bytes', value);
          }
        } finally { this.reader.releaseLock(); this.reader = null; }
      }
    } catch (error) { if (this.connected) this.emit('error', error); }
    finally {
      this.connected = false;
      // Never await close here: close waits for this read task.
      if (!this.closing) queueMicrotask(() => this.close().catch(e => this.emit('error', e)));
    }
  }
  write(bytes) {
    const work = this.queue.then(async () => {
      if (!this.connected || !this.port?.writable) throw new Error('串口未连接');
      const writer = this.port.writable.getWriter();
      try { await writer.write(bytes); } finally { writer.releaseLock(); }
    });
    this.queue = work.catch(() => {}); return work;
  }
  close() {
    if (this.closing) return this.closing;
    this.closing = this.finishClose().finally(() => { this.closing = null; });
    return this.closing;
  }
  async finishClose() {
    this.connected = false;
    try {
      await this.reader?.cancel();
      await this.readTask;
      await this.queue;
      await this.port?.close();
    } finally { this.port = null; this.readTask = null; this.emit('state', 'Disconnected'); }
  }
}
