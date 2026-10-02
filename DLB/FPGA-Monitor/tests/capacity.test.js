import { it, expect } from 'vitest';
import { ChannelStore } from '../src/store/ChannelStore.js';
import { ConfigStore } from '../src/store/ConfigStore.js';
import { FrameLogger } from '../src/logger/FrameLogger.js';
import { decimate } from '../src/chart/ChartController.js';
it('accelerated three-hour 50Hz / 30-channel workload stays within cache/log limits', () => {
  const store = new ChannelStore(new ConfigStore({ getItem: () => null, setItem: () => {} })); store.resetTimeline(0);
  const logger = new FrameLogger();
  const samples = Array.from({ length: 30 }, (_, sourceId) => ({ sourceId, type: 1, rawBits: 0, rawValue: 0, value: 0 }));
  const count = 3 * 60 * 60 * 50;
  for (let i = 0; i < count; i++) {
    const value = i % 1000;
    for (const s of samples) { s.value = value; s.rawValue = value; s.rawBits = value; }
    store.ingest({ seq: i & 65535, hostReceiveTime: i * 20, samples });
    logger.add('RX', `SEQ=${i & 65535}`);
  }
  expect(store.channels.size).toBe(30); expect(store.stats.frames).toBe(540000); expect(store.stats.lost).toBe(0);
  for (const c of store.channels.values()) {
    expect(c.points.size).toBe(20000); expect(c.points.data.length).toBe(20000);
    expect(c.points.values()[0].time).toBe((count - 20000) / 50); expect(c.value).toBe(999);
  }
  expect(logger.entries.length).toBe(2000);
}, 30000);
it('plot decimation preserves isolated extrema within fixed budget', () => {
  const points = Array.from({ length: 20000 }, (_, i) => ({ time: i, value: i === 10001 ? 1000 : i === 10002 ? -1000 : 0 }));
  const plotted = decimate(points); expect(plotted.length).toBeLessThanOrEqual(3000); expect(plotted.some(p => p.value === 1000)).toBe(true); expect(plotted.some(p => p.value === -1000)).toBe(true);
});
