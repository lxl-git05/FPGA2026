export type Direction = 'input' | 'output' | 'inout';
export type Side = 'left' | 'right' | 'top' | 'bottom';
export type Point = { x: number; y: number };
export type Port = { id: string; name: string; direction: Direction; width: string; side: Side; offset?: number };
export type Block = {
  id: string; name: string; kind: 'block' | 'input' | 'output' | 'junction';
  x: number; y: number; w: number; h: number; parent?: string; composite?: boolean;
  collapsed?: boolean; ports: Port[]; note: string; fill: string; fontSize: number;
  expandedSize?: { w: number; h: number };
};
export type Endpoint = { block: string; port: string };
export type Wire = { id: string; source: Endpoint; target: Endpoint; scope?: string; name: string; vertices: Point[]; labelPosition?: number };
export type Project = {
  format: 'fpga-diagram'; schemaVersion: 1; name: string; blocks: Block[]; wires: Wire[];
  view: { zoom: number; x: number; y: number }; style: { fontFamily: string; lineWidth: number };
};
export type ModuleFile = { format: 'fpga-module'; schemaVersion: 1; name: string; root: string; blocks: Block[]; wires: Wire[] };
export const uid = () => crypto.randomUUID();
export const clone = <T>(v: T): T => structuredClone(v);
export const emptyProject = (name = '未命名工程'): Project => ({ format: 'fpga-diagram', schemaVersion: 1, name, blocks: [], wires: [], view: { zoom: 1, x: 0, y: 0 }, style: { fontFamily: 'Georgia, "Microsoft YaHei", serif', lineWidth: 1.5 } });
export const port = (name: string, direction: Direction, width = '1'): Port => ({ id: uid(), name, direction, width, side: direction === 'output' ? 'right' : 'left' });
export function block(name = 'new_module', x = 180, y = 160): Block {
  return { id: uid(), name, kind: 'block', x, y, w: 230, h: 180, ports: [port('clk', 'input'), port('rst_n', 'input'), port('data', 'output', '8')], note: '', fill: '#e7e9eb', fontSize: 22 };
}
export const endpoint = (b: Block, name: string): Endpoint => ({ block: b.id, port: b.ports.find(p => p.name === name)!.id });
export const key = (e: Endpoint) => `${e.block}/${e.port}`;
export function resolve(p: Project, e: Endpoint): { b: Block; p: Port } {
  const b = p.blocks.find(b => b.id === e.block);
  const pt = b?.ports.find(p => p.id === e.port);
  if (!b || !pt) throw Error('连接引用了不存在的模块或端口');
  return { b, p: pt };
}
export function descendants(p: Project, id: string): Set<string> {
  const found = new Set([id]);
  let size = 0;
  while (found.size !== size) { size = found.size; p.blocks.forEach(b => { if (b.parent && found.has(b.parent)) found.add(b.id); }); }
  return found;
}
export function visible(p: Project, b: Block): boolean {
  let parent = b.parent;
  while (parent) { const n = p.blocks.find(n => n.id === parent); if (!n || n.collapsed) return false; parent = n.parent; }
  return true;
}
export function fitContainers(p: Project): void {
  // Coordinates are absolute: growing a container must not move its children.
  const groups=p.blocks.filter(b=>b.composite&&!b.collapsed).sort((a,b)=>descendants(p,a.id).size-descendants(p,b.id).size);
  for(const g of groups){
    const children=p.blocks.filter(b=>b.parent===g.id);if(!children.length)continue;
    const x=Math.min(g.x,...children.map(b=>b.x-50)),y=Math.min(g.y,...children.map(b=>b.y-60));
    const right=Math.max(g.x+g.w,...children.map(b=>b.x+b.w+50)),bottom=Math.max(g.y+g.h,...children.map(b=>b.y+b.h+50));
    const w=right-x,h=bottom-y;
    g.ports.forEach(pt=>{if(pt.offset===undefined)return;const vertical=pt.side==='left'||pt.side==='right';pt.offset=vertical?(g.y+g.h*pt.offset-y)/h:(g.x+g.w*pt.offset-x)/w;});
    g.x=x;g.y=y;g.w=w;g.h=h;
  }
}
export function widthValue(s: string): number | undefined {
  if (/^\d+$/.test(s.trim())) return Number(s);
  const m = s.match(/^\[\s*(\d+)\s*:\s*(\d+)\s*\]$/);
  return m ? Math.abs(Number(m[1]) - Number(m[2])) + 1 : undefined;
}
export function effectiveDirection(b: Block, pt: Port, scope?: string): Direction {
  if (b.id !== scope) return pt.direction;
  return pt.direction === 'input' ? 'output' : pt.direction === 'output' ? 'input' : 'inout';
}
export function connectionScope(p: Project, a: Endpoint, b: Endpoint): string | undefined {
  const aa = resolve(p, a).b, bb = resolve(p, b).b;
  if (aa.parent === bb.parent) return aa.parent;
  if (aa.composite && bb.parent === aa.id) return aa.id;
  if (bb.composite && aa.parent === bb.id) return bb.id;
  throw Error('跨层连接必须经过父模块的外部端口');
}
export function netComponents(p: Project): Map<string, string> {
  const parents = new Map<string, string>();
  const root = (k: string): string => { if (!parents.has(k)) parents.set(k, k); const r = parents.get(k)!; if (r === k) return k; const v = root(r); parents.set(k, v); return v; };
  p.blocks.forEach(b => b.ports.forEach(pt => root(key({ block: b.id, port: pt.id }))));
  p.wires.forEach(w => parents.set(root(key(w.target)), root(key(w.source))));
  return new Map([...parents.keys()].map(k => [k, root(k)]));
}
export function validate(p: Project): string[] {
  const ids = new Set<string>();
  const addID = (id: string) => { if (typeof id !== 'string' || !id || ids.has(id)) throw Error('对象 ID 缺失或重复'); ids.add(id); };
  p.blocks.forEach(b => {
    addID(b.id); if (!b.name.trim()) throw Error('模块名称不能为空');
    if (![b.x, b.y, b.w, b.h, b.fontSize].every(Number.isFinite) || b.w < 8 || b.h < 8 || b.fontSize < 8 || b.fontSize > 80) throw Error('模块位置、尺寸或字号无效');
    const seen = new Set<string>(); let ancestor: Block | undefined = b;
    while (ancestor) { if (seen.has(ancestor.id)) throw Error('模块层级不能形成循环'); seen.add(ancestor.id); const pid: string | undefined = ancestor.parent; ancestor = pid ? p.blocks.find(n => n.id === pid) : undefined; if (pid && (!ancestor || !ancestor.composite)) throw Error('父模块不存在或不是封装模块'); }
    const names = new Set<string>();
    b.ports.forEach(pt => { addID(pt.id); if (!pt.name.trim() || names.has(pt.name)) throw Error('同一模块的端口名称不能为空或重复'); names.add(pt.name); if (!['input','output','inout'].includes(pt.direction) || !['left','right','top','bottom'].includes(pt.side)) throw Error('端口方向或位置无效'); if (!pt.width.trim() || widthValue(pt.width) === 0) throw Error('位宽不能为空或为零'); if (pt.offset !== undefined && (!Number.isFinite(pt.offset) || pt.offset < 0 || pt.offset > 1)) throw Error('端口位置必须在 0–100% 之间'); });
  });
  const pairs = new Set<string>();
  p.wires.forEach(w => {
    addID(w.id); const a = resolve(p, w.source), b = resolve(p, w.target);
    if (key(w.source) === key(w.target)) throw Error('不能连接端口自身');
    for (const end of [a, b]) if (!(end.b.parent === w.scope || (end.b.id === w.scope && end.b.composite))) throw Error('跨层连接必须经过父模块端口');
    const pair = [key(w.source), key(w.target)].sort().join('|');
    if (pairs.has(pair)) throw Error('这两个端口已经连接'); pairs.add(pair);
    if (effectiveDirection(a.b, a.p, w.scope) === 'input' || effectiveDirection(b.b, b.p, w.scope) === 'output') throw Error('方向冲突：请从输出连接到输入；父模块内部方向相反');
    if (!w.vertices.every(v => Number.isFinite(v.x) && Number.isFinite(v.y))) throw Error('连线路径无效');
  });
  const groups = new Map<string, { drivers: string[]; widths: Set<number>; symbolic: boolean; bidir: boolean }>();
  const nets = netComponents(p), attached = new Set(p.wires.flatMap(w => [key(w.source), key(w.target)]));
  p.blocks.forEach(b => b.ports.forEach(pt => {
    const k = key({ block: b.id, port: pt.id }); if (!attached.has(k)) return;
    const root = nets.get(k)!; const group = groups.get(root) ?? { drivers: [], widths: new Set<number>(), symbolic: false, bidir: false };
    if (!b.composite && pt.direction === 'output') group.drivers.push(`${b.name}.${pt.name}`);
    const n = widthValue(pt.width); if (n !== undefined) group.widths.add(n); else group.symbolic = true;
    group.bidir ||= pt.direction === 'inout' && b.kind !== 'junction'; groups.set(root, group);
  }));
  const warnings: string[] = [];
  // Check drivers at each interface level as well as through flattened mappings.
  // An unimplemented composite output still acts as a driver to its siblings.
  for (const scope of new Set(p.wires.map(w => w.scope))) {
    const local = { ...p, wires: p.wires.filter(w => w.scope === scope) };
    const nets = netComponents(local), attached = new Set(local.wires.flatMap(w => [key(w.source),key(w.target)]));
    const drivers = new Map<string,string[]>();
    for (const endpointKey of attached) {
      const [blockID,portID] = endpointKey.split('/'); const end=resolve(p,{block:blockID,port:portID});
      if (effectiveDirection(end.b,end.p,scope) !== 'output') continue;
      const root=nets.get(endpointKey)!,list=drivers.get(root)??[];list.push(`${end.b.name}.${end.p.name}`);drivers.set(root,list);
    }
    for (const list of drivers.values()) if (list.length>1) throw Error(`网络存在多个输出驱动：${list.join('、')}`);
  }
  groups.forEach(g => { if (g.drivers.length > 1) throw Error(`网络存在多个输出驱动：${g.drivers.join('、')}`); if (g.widths.size > 1) throw Error(`位宽不匹配：${[...g.widths].join(' / ')} bit`); if (g.symbolic) warnings.push('符号位宽待检查'); if (g.bidir) warnings.push('inout 网络未进行三态驱动验证'); });
  return warnings;
}
export function addConnection(p: Project, source: Endpoint, target: Endpoint, name = ''): Wire {
  const scope = connectionScope(p, source, target);
  const a = resolve(p, source), b = resolve(p, target);
  if (effectiveDirection(a.b, a.p, scope) === 'input' || effectiveDirection(b.b, b.p, scope) === 'output') [source, target] = [target, source];
  const w: Wire = { id: uid(), source, target, scope, name, vertices: [] };
  const candidate = clone(p); candidate.wires.push(w); validate(candidate); p.wires.push(w); return w;
}
export function groupBlocks(p: Project, selected: string[], name = 'new_module'): Block {
  const roots = p.blocks.filter(b => selected.includes(b.id) && !selected.includes(b.parent ?? ''));
  if (!roots.length) throw Error('请先选择要封装的模块');
  const parent = roots[0].parent;
  if (roots.some(b => b.parent !== parent)) throw Error('只能封装同一层级的模块');
  const members = new Set(roots.flatMap(b => [...descendants(p, b.id)]));
  const all = p.blocks.filter(b => members.has(b.id));
  const x = Math.min(...all.map(b => b.x)) - 100, y = Math.min(...all.map(b => b.y)) - 80;
  const g = block(name, x, y); g.composite = true; g.parent = parent; g.ports = []; g.fill = '#f6f7f8';
  g.w = Math.max(...all.map(b => b.x + b.w)) - x + 100; g.h = Math.max(...all.map(b => b.y + b.h)) - y + 70;
  const nets = netComponents(p), boundary = new Map<string, Port>(), additional: Wire[] = [], internals = new Set<string>();
  p.wires.forEach(w => {
    const s = members.has(w.source.block), t = members.has(w.target.block);
    if (s && t) { if (w.scope === parent) w.scope = g.id; return; }
    if (!s && !t) return;
    const inside = clone(s ? w.source : w.target), nk = nets.get(key(inside))!;
    let pt = boundary.get(nk);
    if (!pt) {
      const original = resolve(p, inside).p;
      pt = port(original.name, original.direction === 'inout' ? 'inout' : s ? 'output' : 'input', original.width);
      const base = pt.name; let n = 2; while (g.ports.some(q => q.name === pt!.name)) pt.name = `${base}_${n++}`;
      g.ports.push(pt); boundary.set(nk, pt);
    }
    const outer = { block: g.id, port: pt.id };
    if (s) w.source = outer; else w.target = outer;
    const linkKey = `${pt.id}/${key(inside)}`;
    if (!internals.has(linkKey)) { additional.push({ id: uid(), source: s ? inside : outer, target: s ? outer : inside, scope: g.id, name: '', vertices: [] }); internals.add(linkKey); }
  });
  // Fan-out crossings can collapse to the same external pair.
  const seen = new Set<string>(); p.wires = p.wires.filter(w => { const k = [key(w.source), key(w.target)].sort().join('|'); if (seen.has(k)) return false; seen.add(k); return true; });
  roots.forEach(b => b.parent = g.id); p.blocks.push(g); p.wires.push(...additional); validate(p); return g;
}
export function ungroup(p: Project, id: string): void {
  const g = p.blocks.find(b => b.id === id); if (!g?.composite) throw Error('请选择封装模块');
  if (g.collapsed) toggleCollapse(p, g.id);
  // Keep every boundary as an explicit junction so fan-out and chained mappings survive.
  g.ports.forEach(pt => {
    const incident = p.wires.filter(w => [w.source, w.target].some(e => e.block === id && e.port === pt.id));
    if (!incident.length) return;
    const j = block(pt.name, g.x + (pt.side === 'right' ? g.w : 0), g.y + 50 + g.ports.indexOf(pt) * 35);
    j.kind = 'junction'; j.w = j.h = 10; j.parent = g.parent; j.ports = [port(pt.name, 'inout', pt.width)]; j.ports[0].side = 'left';
    p.blocks.push(j);
    incident.forEach(w => { for (const field of ['source','target'] as const) if (w[field].block === id && w[field].port === pt.id) w[field] = { block: j.id, port: j.ports[0].id }; });
  });
  p.blocks.forEach(b => { if (b.parent === id) b.parent = g.parent; }); p.wires.forEach(w => { if (w.scope === id) w.scope = g.parent; });
  p.blocks = p.blocks.filter(b => b.id !== id); validate(p);
}
export function toggleCollapse(p: Project, id: string): void {
  const b = p.blocks.find(b => b.id === id); if (!b?.composite) throw Error('请选择封装模块');
  if (b.collapsed) { b.w = b.expandedSize?.w ?? 600; b.h = b.expandedSize?.h ?? 400; b.collapsed = false; }
  else { b.expandedSize = { w: b.w, h: b.h }; b.w = 250; b.h = Math.max(150, b.ports.length * 30 + 40); b.collapsed = true; }
}
export function moduleFile(p: Project, id: string): ModuleFile {
  const b = p.blocks.find(b => b.id === id); if (!b) throw Error('请选择一个模块');
  const ids = descendants(p, id), blocks = clone(p.blocks.filter(b => ids.has(b.id)));
  blocks.find(b => b.id === id)!.parent = undefined;
  return { format: 'fpga-module', schemaVersion: 1, name: b.name, root: id, blocks, wires: clone(p.wires.filter(w => ids.has(w.source.block) && ids.has(w.target.block) && (w.scope === undefined || ids.has(w.scope)))) };
}
export function instantiate(p: Project, m: ModuleFile, at: Point, parent?: string): string {
  const copy = clone(m), root = copy.blocks.find(b => b.id === copy.root); if (!root) throw Error('模块根节点不存在');
  const dx = at.x - root.x, dy = at.y - root.y, ids = new Map<string,string>();
  copy.blocks.forEach(b => { ids.set(b.id, uid()); b.ports.forEach(pt => ids.set(pt.id, uid())); });
  const rootID = ids.get(root.id)!;
  copy.blocks.forEach(b => { b.id = ids.get(b.id)!; b.parent = b.parent ? ids.get(b.parent) : parent; b.x += dx; b.y += dy; b.ports.forEach(pt => pt.id = ids.get(pt.id)!); });
  copy.wires.forEach(w => { w.id = uid(); for (const field of ['source','target'] as const) w[field] = { block: ids.get(w[field].block)!, port: ids.get(w[field].port)! }; w.scope = w.scope ? ids.get(w.scope) : parent; w.vertices.forEach(v => { v.x += dx; v.y += dy; }); });
  p.blocks.push(...copy.blocks); p.wires.push(...copy.wires); validate(p); return rootID;
}
export function parseFile(text: string): Project | ModuleFile {
  const raw = JSON.parse(text);
  if (!raw || !['fpga-diagram','fpga-module'].includes(raw.format) || raw.schemaVersion !== 1) throw Error('不支持的文件格式或版本（需要版本 1）');
  if (!Array.isArray(raw.blocks) || !Array.isArray(raw.wires) || raw.blocks.length > 10000 || raw.wires.length > 50000) throw Error('文件结构无效或图形数量超过限制');
  const str = (v: unknown, fallback = '') => typeof v === 'string' ? v : fallback;
  const p = emptyProject(str(raw.name, '导入工程'));
  p.blocks = raw.blocks.map((b: any): Block => {
    if (!b || !Array.isArray(b.ports)) throw Error('模块端口数据无效');
    if (!['block','input','output','junction'].includes(b.kind)) throw Error('未知模块类型');
    return { id: str(b.id), name: str(b.name), kind: b.kind, x: b.x, y: b.y, w: b.w, h: b.h, parent: b.parent == null ? undefined : str(b.parent), composite: !!b.composite, collapsed: !!b.collapsed, expandedSize: b.expandedSize && { w: Number(b.expandedSize.w), h: Number(b.expandedSize.h) }, note: str(b.note), fill: /^#[0-9a-f]{6}$/i.test(b.fill) ? b.fill : '#e7e9eb', fontSize: b.fontSize ?? 22, ports: b.ports.map((pt: any) => ({ id: str(pt.id), name: str(pt.name), direction: pt.direction, width: str(pt.width), side: pt.side, offset: pt.offset })) };
  });
  p.wires = raw.wires.map((w: any) => ({ id: str(w.id), source: { block: str(w.source?.block), port: str(w.source?.port) }, target: { block: str(w.target?.block), port: str(w.target?.port) }, scope: w.scope == null ? undefined : str(w.scope), name: str(w.name), labelPosition: Number.isFinite(w.labelPosition) ? Math.max(0, Math.min(1, w.labelPosition)) : undefined, vertices: Array.isArray(w.vertices) ? w.vertices.map((v: any) => ({ x: v.x, y: v.y })) : [] }));
  if (raw.view && [raw.view.zoom, raw.view.x, raw.view.y].every(Number.isFinite)) p.view = { zoom: Math.max(.15, Math.min(3, raw.view.zoom)), x: raw.view.x, y: raw.view.y };
  const fonts = ['Georgia, "Microsoft YaHei", serif', 'Arial, "Microsoft YaHei", sans-serif', 'Consolas, "Microsoft YaHei", monospace'];
  if (raw.style) { if (fonts.includes(raw.style.fontFamily)) p.style.fontFamily = raw.style.fontFamily; if (Number.isFinite(raw.style.lineWidth)) p.style.lineWidth = Math.max(.5, Math.min(6, raw.style.lineWidth)); }
  validate(p);
  if (raw.format === 'fpga-module') {
    const roots = p.blocks.filter(b => !b.parent);
    if (roots.length !== 1 || roots[0].id !== raw.root) throw Error('模块包必须包含唯一根模块');
    return { format: 'fpga-module', schemaVersion: 1, name: p.name, root: raw.root, blocks: p.blocks, wires: p.wires };
  }
  return p;
}
