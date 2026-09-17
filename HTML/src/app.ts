import { Graph, Shape, Selection, Transform, Snapline, Export, type Node, type Edge } from '@antv/x6';
import { addConnection, block, clone, descendants, emptyProject, fitContainers, groupBlocks, instantiate, moduleFile, parseFile, port, resolve, toggleCollapse, ungroup, validate, visible, widthValue, type Block, type ModuleFile, type Port, type Project } from './model';
import { keyExample, terminal, uartExample } from './examples';

const $ = <T extends HTMLElement = HTMLElement>(selector: string) => document.querySelector<T>(selector)!;
const esc = (v: unknown) => String(v).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]!));
const draftKey = 'fpga-block-studio-draft-v1', libraryKey = 'fpga-block-studio-library-v1';
let project = uartExample(), rendering = false, dirty = false, savedTimer = 0, toastTimer = 0, grid = true;
let history: Project[] = [], future: Project[] = [], clipboard: ModuleFile[] = [], clipboardGrouped = false, selection: string[] = [], library: ModuleFile[] = [], pendingDraft: string | null = null;
let fileMode: 'open' | 'module' = 'open', dragSnapshot: Project | undefined;
function toast(message: string, error = false) { const el = $('#toast'); el.textContent = message; el.className = `show${error ? ' error' : ''}`; clearTimeout(toastTimer); toastTimer = window.setTimeout(() => el.className = '', error ? 6000 : 3500); }
function fail(e: unknown) { toast(e instanceof Error ? e.message : String(e), true); }
try { pendingDraft = localStorage.getItem(draftKey); const saved = JSON.parse(localStorage.getItem(libraryKey) ?? '[]'); if (Array.isArray(saved)) library = saved.map(m => parseFile(JSON.stringify(m))).filter((m): m is ModuleFile => m.format === 'fpga-module'); } catch { /* File import/export remains available if storage is blocked. */ }

const graph = new Graph({
  container: $('#canvas'), autoResize: true, async: false,
  background: { color: '#fafbfc' }, grid: { size: 10, visible: true, type: 'dot', args: { color: '#d7dfe4', thickness: 1 } },
  panning: { enabled: true, eventTypes: ['mouseWheelDown'] }, mousewheel: { enabled: true, modifiers: null, minScale: .15, maxScale: 3 },
  scaling: { min: .15, max: 3 }, interacting: { edgeLabelMovable: false, arrowheadMovable: false },
  connecting: {
    snap: { radius: 18 }, allowBlank: false, allowNode: false, allowEdge: false, allowLoop: true, allowMulti: 'withPort',
    anchor: 'center', connectionPoint: 'anchor', router: { name: 'orth', args: { padding: 20 } }, connector: 'normal',
    createEdge: () => new Shape.Edge({ attrs: { line: { stroke: '#1f2b31', strokeWidth: project.style.lineWidth, targetMarker: { name: 'block', width: 8, height: 6 } } } }),
    validateConnection: ({ sourceCell, targetCell, sourcePort, targetPort }) => !!sourceCell && !!targetCell && !!sourcePort && !!targetPort,
    validateEdge: ({ edge }) => {
      try { const p = clone(project); addConnection(p, { block: edge.getSourceCellId()!, port: edge.getSourcePortId()! }, { block: edge.getTargetCellId()!, port: edge.getTargetPortId()! }); return true; }
      catch (e) { fail(e); return false; }
    },
  },
});
graph.use(new Selection({ enabled: true, multiple: true, rubberband: true, modifiers: ['shift'], multipleSelectionModifiers: ['shift','ctrl','meta'], showNodeSelectionBox: true, showEdgeSelectionBox: false, pointerEvents: 'none' }));
graph.use(new Transform({ resizing: { enabled: node => project.blocks.find(b => b.id === node.id)?.kind === 'block', minWidth: 100, minHeight: 80 }, rotating: false }));
graph.use(new Snapline({ enabled: true })); graph.use(new Export());

// Capture right-button gestures before X6's node/port handlers can select or drag.
let rightPan: { x: number; y: number; tx: number; ty: number } | undefined;
let suppressContextUntil = 0;
function endRightPan() {
  if (!rightPan) return;
  rightPan = undefined;
  suppressContextUntil = Date.now() + 250;
  document.body.classList.remove('canvas-panning');
  captureView(); storeDraft(); updateInfo();
}
$('#canvas').addEventListener('mousedown', e => {
  if (e.button !== 2) return;
  e.preventDefault(); e.stopImmediatePropagation();
  if (e.buttons & 1) return;
  const t = graph.translate();
  rightPan = { x: e.clientX, y: e.clientY, tx: t.tx, ty: t.ty };
  document.body.classList.add('canvas-panning');
  $('#status').textContent = '正在平移画布 · 松开右键结束';
}, true);
window.addEventListener('mousemove', e => {
  if (!rightPan) return;
  if (!(e.buttons & 2)) { endRightPan(); return; }
  e.preventDefault(); e.stopImmediatePropagation();
  graph.translate(rightPan.tx + e.clientX - rightPan.x, rightPan.ty + e.clientY - rightPan.y);
}, true);
window.addEventListener('mouseup', e => {
  if (!rightPan || e.button !== 2) return;
  e.preventDefault(); e.stopImmediatePropagation(); endRightPan();
}, true);
window.addEventListener('blur', endRightPan);
window.addEventListener('contextmenu', e => {
  if (rightPan || Date.now() < suppressContextUntil || (e.target as HTMLElement).closest('#canvas')) {
    e.preventDefault(); e.stopImmediatePropagation();
  }
}, true);

function selectedBlock(): Block | undefined { return selection.length === 1 ? project.blocks.find(b => b.id === selection[0]) : undefined; }
function captureView() { const t = graph.translate(); project.view = { zoom: graph.zoom(), x: t.tx, y: t.ty }; }
function storeDraft() {
  if (pendingDraft) return;
  clearTimeout(savedTimer); savedTimer = window.setTimeout(() => { captureView(); try { localStorage.setItem(draftKey, JSON.stringify(project)); $('#save-state').textContent = `草稿已保存 · ${new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'})}`; } catch { $('#save-state').textContent = '浏览器草稿不可用，请保存工程文件'; } }, 450);
}
function pushHistory(before: Project) { history.push(before); if (history.length > 80) history.shift(); future = []; dirty = true; storeDraft(); }
function transact(label: string, action: () => void) {
  captureView(); const before = clone(project);
  try { action(); fitContainers(project); validate(project); pushHistory(before); render(); toast(label); }
  catch (e) { project = before; render(); fail(e); }
}
function portText(pt: Port) { return pt.name + (pt.width === '1' ? '' : /^\[/.test(pt.width) ? pt.width : /^\d+$/.test(pt.width) ? `[${Number(pt.width)-1}:0]` : `[${pt.width}]`); }
function depth(p: Project, b: Block) { let n = 0, parent = b.parent; while (parent) { n++; parent = p.blocks.find(b => b.id === parent)?.parent; } return n; }
function renderGraph(g: Graph, p: Project) {
  g.clearCells();
  const sorted = [...p.blocks].sort((a,b) => depth(p,a)-depth(p,b));
  for (const b of sorted) {
    const expanded = b.composite && !b.collapsed, junction = b.kind === 'junction', terminalNode = b.kind === 'input' || b.kind === 'output';
    const attrs: any = {
      body: { fill: junction ? '#1b292d' : terminalNode ? 'transparent' : b.fill, stroke: terminalNode ? 'none' : '#27343b', strokeWidth: p.style.lineWidth, rx: junction ? 5 : 1, ry: junction ? 5 : 1 },
      label: { text: terminalNode && b.ports[0] ? portText({...b.ports[0],name:b.name}) : b.name, fontFamily: p.style.fontFamily, fontSize: b.fontSize, fill: '#1c292e', refX: .5, refY: expanded ? 28 : terminalNode ? 5 : .5, textAnchor: 'middle', textVerticalAnchor: terminalNode ? 'bottom' : 'middle', display: junction ? 'none' : 'block' },
      lead: { d: `M 0 18 H ${b.w}`, stroke:'#29383e', strokeWidth:p.style.lineWidth, fill:'none' },
      arrow: { d: b.kind==='output' ? `M ${b.w} 18 L ${b.w-8} 14 L ${b.w-8} 22 Z` : '', fill:'#29383e', stroke:'none' },
    };
    const items = b.ports.map(pt => {
      const sameSide = b.ports.filter(q => q.side === pt.side), index = sameSide.indexOf(pt), vertical = pt.side === 'left' || pt.side === 'right';
      const f = (index + 1) / (sameSide.length + 1);
      const offset = b.collapsed ? undefined : pt.offset;
      const pos = junction ? { x: 5, y: 5 } : terminalNode ? { x: pt.side === 'left' ? 0 : b.w, y: 18 } : vertical ? { x: pt.side === 'left' ? 0 : b.w, y: offset !== undefined ? b.h * offset : 45 + (b.h - 65) * f } : { x: b.w * (offset ?? f), y: pt.side === 'top' ? 0 : b.h };
      return { id: pt.id, group: 'ports', args: pos, attrs: {
        circle: { r: junction ? 5 : 4, magnet: true, stroke: '#607e83', strokeWidth: 1, fill: '#fff', opacity: junction ? 0 : 1 },
        portLabel: { text: terminalNode || junction ? '' : portText(pt), fontFamily: p.style.fontFamily, fontSize: 13, fill: '#34454c', x: vertical ? pt.side === 'left' ? -10 : 10 : 0, y: vertical ? -7 : pt.side === 'top' ? -10 : 19, textAnchor: vertical ? pt.side === 'left' ? 'end' : 'start' : 'middle' },
      } };
    });
    const n = g.addNode({ id: b.id, shape: 'rect', markup: terminalNode ? [{tagName:'rect',selector:'body'},{tagName:'path',selector:'lead'},{tagName:'path',selector:'arrow'},{tagName:'text',selector:'label'}] : undefined, x: b.x, y: b.y, width: b.w, height: b.h, zIndex: depth(p,b)*10 + (expanded ? 0 : 3), attrs, ports: { groups: { ports: { position: 'absolute', markup: [{ tagName: 'circle', selector: 'circle' }, { tagName: 'text', selector: 'portLabel' }] } }, items }, visible: visible(p,b), data: { kind: b.kind } });
    if (b.parent) g.getCellById(b.parent)?.addChild(n);
  }
  for (const w of p.wires) {
    const scope = w.scope ? p.blocks.find(b => b.id === w.scope) : undefined;
    const a = p.blocks.find(b => b.id === w.source.block)!, b = p.blocks.find(b => b.id === w.target.block)!;
    const show = visible(p,a) && visible(p,b) && !scope?.collapsed;
    const symbolic = [resolve(p,w.source).p, resolve(p,w.target).p].some(pt => widthValue(pt.width) === undefined);
    const e = g.addEdge({ id: w.id, source: { cell: w.source.block, port: w.source.port, connectionPoint: 'anchor' }, target: { cell: w.target.block, port: w.target.port, connectionPoint: 'anchor' }, vertices: w.vertices, router: { name: 'orth', args: { padding: 18 } }, connector: 'normal', zIndex: (scope ? depth(p,scope)+1 : 0)*10 + 2, visible: show,
      attrs: { line: { stroke: '#29383e', strokeWidth: p.style.lineWidth, strokeDasharray: symbolic ? '5 3' : '', targetMarker: b.composite || b.kind === 'output' || b.kind === 'junction' || resolve(p,w.target).p.direction === 'inout' ? null : { name: 'block', width: 8, height: 6 } } },
      labels: w.name ? [{ attrs: { label: { text: w.name, fontFamily: p.style.fontFamily, fontSize: 12, fill: '#3b515b' }, body: { fill: '#fafbfc', stroke: 'none', rx: 2, ry: 2 } }, position: { distance: w.labelPosition ?? .5, offset: -11 } }] : [],
    });
    if (scope) g.getCellById(scope.id)?.addChild(e);
  }
}
function render() {
  rendering = true; graph.getPlugin<Transform>('transform')?.clearWidgets();
  renderGraph(graph,project); graph.zoomTo(project.view.zoom); graph.translate(project.view.x,project.view.y);
  selection = selection.filter(id => graph.getCellById(id)?.isVisible()); graph.resetSelection(selection);
  rendering = false; updateSelection(); updateInfo();
}
function updateInfo() {
  $('#project-name').setAttribute('title',project.name); $<HTMLInputElement>('#project-name').value = project.name;
  $('#canvas-title').textContent = project.name; $('#canvas-meta').textContent = `${project.blocks.filter(b=>b.kind==='block').length} 模块 / ${project.wires.length} 连线`;
  $('#status').textContent = selection.length ? `已选择 ${selection.length} 个对象` : '就绪 · 从左侧添加模块，拖动端口连接';
  const warnings = validate(project); $('#warnings').textContent = warnings.length ? `${warnings.length} 项待检查` : '连接检查通过'; $('#warnings').title = [...new Set(warnings)].join('\n');
  $<HTMLButtonElement>('[data-action="undo"]').disabled = history.length === 0; $<HTMLButtonElement>('[data-action="redo"]').disabled = future.length === 0;
  $('#zoom-value').textContent = `${Math.round(graph.zoom()*100)}%`;
}
function updateSelection() {
  graph.getEdges().forEach(e => e.removeTools());
  selection.forEach(id => { const c = graph.getCellById(id); if (c?.isEdge()) c.addTools([{name:'vertices'}, {name:'segments'}]); });
  inspector(); if (!rendering) updateInfo();
}
graph.on('selection:changed', () => { if (!rendering) { selection = graph.getSelectedCells().map(c=>c.id); updateSelection(); } });
graph.on('node:dblclick', ({node}) => { if (project.blocks.find(b=>b.id===node.id)?.composite) transact('已切换模块视图',()=>toggleCollapse(project,node.id)); else { selection=[node.id]; graph.resetSelection(selection); editPorts(); } });
graph.on('edge:connected', ({edge,isNew}) => { if (rendering || !isNew) return; const a={block:edge.getSourceCellId()!,port:edge.getSourcePortId()!},b={block:edge.getTargetCellId()!,port:edge.getTargetPortId()!}; setTimeout(()=>transact('已连接端口',()=>{ const w=addConnection(project,a,b);selection=[w.id]; }),0); });
graph.on('node:mousedown', () => { if (!rendering) { captureView();dragSnapshot=clone(project); } });
graph.on('edge:mousedown', () => { if (!rendering) { captureView();dragSnapshot=clone(project); } });
graph.on('node:change:position',({node})=>{if(rendering)return;const b=project.blocks.find(b=>b.id===node.id);if(b){const pos=node.position();b.x=pos.x;b.y=pos.y;}});
graph.on('node:change:size',({node})=>{if(rendering)return;const b=project.blocks.find(b=>b.id===node.id);if(b){if(!dragSnapshot)dragSnapshot=clone(project);const size=node.size();b.w=size.width;b.h=size.height;}});
graph.on('edge:change:vertices',({edge})=>{if(rendering)return;const w=project.wires.find(w=>w.id===edge.id);if(w){if(!dragSnapshot)dragSnapshot=clone(project);w.vertices=edge.getVertices().map(v=>({x:v.x,y:v.y}));}});
window.addEventListener('pointerup',()=>{setTimeout(()=>{if(dragSnapshot){const before=dragSnapshot;dragSnapshot=undefined;if(JSON.stringify(before.blocks)!==JSON.stringify(project.blocks)||JSON.stringify(before.wires)!==JSON.stringify(project.wires)){fitContainers(project);pushHistory(before);captureView();render();}}},20);});
graph.on('scale',()=>{if(!rendering){$('#zoom-value').textContent=`${Math.round(graph.zoom()*100)}%`;storeDraft();}});
graph.on('translate',()=>{if(!rendering)storeDraft();});

function inspector() {
  const b=selectedBlock(),w=selection.length===1?project.wires.find(w=>w.id===selection[0]):undefined;
  $('#selection-kind').textContent=b?b.composite?'GROUP':'MODULE':w?'SIGNAL':selection.length?'SELECTION':'PROJECT';
  if(b){
    $('#inspector').innerHTML=`<div class="inspector-title"><span>${b.composite?'▣':'▭'}</span><div><strong>${esc(b.name)}</strong><small>${b.composite?'封装模块 · 保留内部结构':b.kind==='junction'?'信号分支连接点':b.kind==='block'?'自定义模块':'顶层接口'}</small></div></div>
      <label>模块名称</label><input id="block-name" value="${esc(b.name)}"><label>说明</label><textarea id="block-note" rows="2" placeholder="描述模块功能…">${esc(b.note)}</textarea>
      <h3>端口 <span class="subtle">${b.ports.length}</span></h3>${b.ports.map(pt=>`<div class="port-summary ${pt.direction==='output'?'out':''}"><span>${pt.direction==='input'?'IN':pt.direction==='output'?'OUT':'I/O'}</span><b>${esc(pt.name)}</b><em>${esc(pt.width)} bit</em></div>`).join('')}
      <button class="wide" data-action="edit-ports">编辑端口 / 批量添加</button>
      <div class="row"><div><label>宽度</label><input type="number" min="${b.kind==='junction'?10:80}" id="block-w" value="${Math.round(b.w)}"></div><div><label>高度</label><input type="number" min="${b.kind==='junction'?10:30}" id="block-h" value="${Math.round(b.h)}"></div></div>
      <div class="row"><div><label>填充颜色</label><input type="color" id="block-fill" value="${b.fill}"></div><div><label>字号</label><input type="number" min="8" max="80" id="block-font" value="${b.fontSize}"></div></div>
      <hr><button class="wide primary" data-action="library-add">＋ 保存到我的模块</button><button class="wide" data-action="export-module">导出模块包 ↗</button>${b.composite?'<button class="wide" data-action="collapse">展开 / 折叠内部结构</button><button class="wide danger" data-action="ungroup">解除封装</button>':''}
      <div class="selection-note">${b.parent?'此模块属于上层封装，跨层连接请经过父模块端口。':'拖动端口圆点连接信号。方向与已知位宽会在连接时自动检查。'}</div>`;
    const bind=(id:string,field:keyof Block,numeric=false)=>$(id).addEventListener('change',()=>transact('模块属性已更新',()=>{const value=$<HTMLInputElement>(id).value;(b as any)[field]=numeric?Number(value):value;}));
    bind('#block-name','name');bind('#block-note','note');bind('#block-w','w',true);bind('#block-h','h',true);bind('#block-fill','fill');bind('#block-font','fontSize',true);
  } else if(w){
    const a=resolve(project,w.source),b=resolve(project,w.target);
    $('#inspector').innerHTML=`<div class="inspector-title"><span>→</span><div><strong>信号连接</strong><small>直角折线</small></div></div><label>信号名称</label><input id="wire-name" value="${esc(w.name)}" placeholder="可选，例如 data[7:0]"><h3>连接端点</h3><p>${esc(a.b.name)}.${esc(a.p.name)}<br>↓<br>${esc(b.b.name)}.${esc(b.p.name)}</p><label>标签位置（沿线 0–100%）</label><input id="wire-label-position" type="number" min="0" max="100" value="${Math.round(((w as any).labelPosition??.5)*100)}"><button class="wide" data-action="reset-route">重置折线路径</button><button class="wide" data-action="split-wire">在线上插入分支连接点</button><div class="selection-note">拖动线上的控制点调整拐点，拖动线段改变走线。分支须使用连接点，交叉线不会自动相连。</div>`;
    $('#wire-name').addEventListener('change',()=>transact('信号名称已更新',()=>w.name=$<HTMLInputElement>('#wire-name').value));
    // Label positions are committed into the explicit schema below.
    $('#wire-label-position').addEventListener('change',()=>transact('标签位置已更新',()=>w.labelPosition=Math.max(0,Math.min(1,Number($<HTMLInputElement>('#wire-label-position').value)/100))));
  } else {
    $('#inspector').innerHTML=`<div class="inspector-title"><span>▧</span><div><strong>${selection.length?`已选 ${selection.length} 个对象`:'开始构思你的模块'}</strong><small>${selection.length?'封装 · 对齐 · 复制':'选择模块以编辑属性'}</small></div></div><h3>工程样式</h3><label>图形字体</label><select id="font-family"><option value='Georgia, "Microsoft YaHei", serif'>衬线 · 论文框图</option><option value='Arial, "Microsoft YaHei", sans-serif'>无衬线 · 简洁</option><option value='Consolas, "Microsoft YaHei", monospace'>等宽 · 工程</option></select><label>连线 / 边框宽度</label><input id="line-width" type="number" min="0.5" max="6" step="0.5" value="${project.style.lineWidth}"><hr><h3>连接规则</h3><p>输出 → 输入，支持一对多。<br>拒绝方向冲突、多输出驱动和已知位宽不匹配。<br>符号位宽以虚线提示待检查。</p><h3>模块化工作流</h3><p>① 添加模块并配置端口<br>② 拖动端口完成信号连接<br>③ Shift 多选后封装为模块<br>④ 保存模块包，在其他工程导入</p><div class="selection-note">保存工程保留所有可编辑数据。图片适合文档展示；模块包适合跨工程复用。</div>`;
    $<HTMLSelectElement>('#font-family').value=project.style.fontFamily;
    $('#font-family').addEventListener('change',()=>transact('字体已更新',()=>project.style.fontFamily=$<HTMLSelectElement>('#font-family').value));
    $('#line-width').addEventListener('change',()=>transact('线宽已更新',()=>project.style.lineWidth=Math.max(.5,Math.min(6,Number($<HTMLInputElement>('#line-width').value)))));
  }
}

function modal(title:string,body:string,buttons:{text:string;primary?:boolean;action:()=>void|Promise<void>}[]){
  $('#modal-title').textContent=title;$('#modal-body').innerHTML=body;$('#modal-actions').innerHTML='';
  buttons.forEach(b=>{const button=document.createElement('button');button.textContent=b.text;if(b.primary)button.className='primary';button.onclick=()=>{try{Promise.resolve(b.action()).catch(fail);}catch(e){fail(e);}};$('#modal-actions').append(button);});
  $<HTMLDialogElement>('#modal').showModal();
}
const closeModal=()=> $<HTMLDialogElement>('#modal').close();$('#modal-close').onclick=closeModal;
function confirmAction(title:string,message:string,action:()=>void){modal(title,`<p>${esc(message)}</p>`,[{text:'取消',action:closeModal},{text:'确认',primary:true,action:()=>{closeModal();action();}}]);}
function askName(title:string,initial:string,action:(name:string)=>void){modal(title,`<label>名称</label><input id="new-name" value="${esc(initial)}">`,[{text:'取消',action:closeModal},{text:'确定',primary:true,action:()=>{const value=$<HTMLInputElement>('#new-name').value.trim();if(!value)return toast('请输入名称',true);closeModal();action(value);}}]);$<HTMLInputElement>('#new-name').select();}
function editPorts(){
  const b=selectedBlock();if(!b)return toast('请先选择一个模块',true);let rows=clone(b.ports);
  modal(`编辑端口 · ${b.name}`,`<p>方向以模块外部为准；封装内部的方向会自动反转。位宽填写 1、8、[7:0] 或符号表达式。</p><table class="port-table"><thead><tr><th>端口名称</th><th>方向</th><th>位宽</th><th>位置</th><th></th></tr></thead><tbody id="port-rows"></tbody></table><button id="port-add">＋ 添加端口</button><label>批量添加（每行：方向 名称 位宽）</label><textarea id="bulk-ports" rows="3" placeholder="input clk 1&#10;input data [DATA_WIDTH-1:0]&#10;output done 1"></textarea><button id="bulk-add">追加上述端口</button><div class="modal-error" id="port-error"></div>`,[{text:'取消',action:closeModal},{text:'应用端口',primary:true,action:()=>{
    try{readRows();const removed=b.ports.filter(pt=>!rows.some(q=>q.id===pt.id));const linked=project.wires.filter(w=>[w.source,w.target].some(e=>e.block===b.id&&removed.some(pt=>pt.id===e.port)));if(linked.length&&!window.confirm(`删除端口将删除 ${linked.length} 条关联连线，是否继续？`))return;
      const candidate=clone(project);candidate.blocks.find(n=>n.id===b.id)!.ports=rows;candidate.wires=candidate.wires.filter(w=>!linked.some(e=>e.id===w.id));validate(candidate);closeModal();transact('端口已更新',()=>{project=candidate;});
    }catch(e){$('#port-error').textContent=e instanceof Error?e.message:String(e);}
  }}]);
  function readRows(){rows=rows.map((pt,i)=>{const el=$(`#port-row-${i}`),offset=(el.querySelector('[data-field="offset"]') as HTMLInputElement).value;return {...pt,name:(el.querySelector('[data-field="name"]') as HTMLInputElement).value.trim(),direction:(el.querySelector('[data-field="direction"]') as HTMLSelectElement).value as Port['direction'],width:(el.querySelector('[data-field="width"]') as HTMLInputElement).value.trim(),side:(el.querySelector('[data-field="side"]') as HTMLSelectElement).value as Port['side'],offset:offset===''?undefined:Number(offset)/100};});}
  function paintRows(){ $('#port-rows').innerHTML=rows.map((pt,i)=>`<tr id="port-row-${i}"><td><input data-field="name" aria-label="端口 ${i+1} 名称" value="${esc(pt.name)}"></td><td><select data-field="direction">${['input','output','inout'].map(d=>`<option ${d===pt.direction?'selected':''}>${d}</option>`).join('')}</select></td><td><input data-field="width" value="${esc(pt.width)}"></td><td><select data-field="side">${[['left','左'],['right','右'],['top','上'],['bottom','下']].map(([v,l])=>`<option value="${v}" ${v===pt.side?'selected':''}>${l}</option>`).join('')}</select></td><td><button data-up="${i}" title="上移">↑</button><button data-remove="${i}" title="删除">×</button></td></tr>`).join('');
    rows.forEach((pt,i)=>{const row=$(`#port-row-${i}`),td=document.createElement('td');td.innerHTML=`<input data-field="offset" type="number" min="0" max="100" step="0.1" aria-label="端口位置百分比" placeholder="自动" value="${pt.offset===undefined?'':Math.round(pt.offset*1000)/10}">`;td.style.width='80px';row.insertBefore(td,row.lastElementChild);});
    $('#port-rows').querySelectorAll<HTMLButtonElement>('[data-remove]').forEach(el=>el.onclick=()=>{readRows();rows.splice(Number(el.dataset.remove),1);paintRows();});
    $('#port-rows').querySelectorAll<HTMLButtonElement>('[data-up]').forEach(el=>el.onclick=()=>{readRows();const i=Number(el.dataset.up);if(i>0)[rows[i-1],rows[i]]=[rows[i],rows[i-1]];paintRows();});
  }
  const header=$('.port-table thead tr'),positionHeader=document.createElement('th');positionHeader.textContent='位置 %';header.insertBefore(positionHeader,header.lastElementChild);
  $('#port-add').onclick=()=>{readRows();rows.push(port(`port_${rows.length+1}`,'input'));paintRows();};
  $('#bulk-add').onclick=()=>{try{readRows();const added=$<HTMLTextAreaElement>('#bulk-ports').value.split('\n').filter(l=>l.trim()).map(l=>{const m=l.trim().match(/^(input|output|inout)\s+(\S+)(?:\s+(.+))?$/);if(!m)throw Error(`格式错误：${l}`);return port(m[2],m[1] as Port['direction'],m[3]??'1');});rows.push(...added);paintRows();$<HTMLTextAreaElement>('#bulk-ports').value='';$('#port-error').textContent='';}catch(e){$('#port-error').textContent=String(e);}};paintRows();
}

function center(){ const r=$('#canvas').getBoundingClientRect();return graph.clientToLocal(r.x+r.width/2,r.y+r.height/2); }
function addBlock(kind:Block['kind']){const at=center(),parent=selectedBlock();transact('已添加元件',()=>{let b=kind==='input'||kind==='output'?terminal(kind==='input'?'signal_in':'signal_out',kind,at.x-60,at.y-20):block('new_module',at.x-110,at.y-80);if(kind==='junction'){b.kind=kind;b.w=b.h=10;b.ports=[port('signal','inout')];}if(parent?.composite&&!parent.collapsed){b.parent=parent.id;b.x=parent.x+100;b.y=parent.y+100;}project.blocks.push(b);selection=[b.id];});}
function load(p:Project,fitView=false){pendingDraft=null;$('#recovery').hidden=true;project=p;selection=[];history=[];future=[];dirty=false;render();if(fitView)fit();storeDraft();}
function fit(){graph.zoomToFit({padding:85,maxScale:1.05,minScale:.15});captureView();updateInfo();}
function deleteSelection(){
  const ids=new Set(selection.flatMap(id=>project.blocks.some(b=>b.id===id)?[...descendants(project,id)]:[id]));if(!ids.size)return;
  const affected=project.wires.filter(w=>ids.has(w.id)||ids.has(w.source.block)||ids.has(w.target.block));
  confirmAction('删除所选对象',`将删除 ${project.blocks.filter(b=>ids.has(b.id)).length} 个模块/元件及 ${affected.length} 条连线，可撤销。`,()=>transact('已删除',()=>{project.blocks=project.blocks.filter(b=>!ids.has(b.id));project.wires=project.wires.filter(w=>!affected.includes(w));selection=[];}));
}
function copy(){const roots=project.blocks.filter(b=>selection.includes(b.id)&&!selection.includes(b.parent??''));if(!roots.length)return toast('请先选择模块',true);if(roots.some(b=>b.parent!==roots[0].parent))return toast('请复制同层模块，或直接复制它们的共同父模块',true);clipboardGrouped=roots.length>1;if(clipboardGrouped){const p=clone(project),ids=new Set(roots.flatMap(b=>[...descendants(p,b.id)]));p.wires=p.wires.filter(w=>ids.has(w.source.block)&&ids.has(w.target.block));const group=groupBlocks(p,roots.map(b=>b.id),'clipboard');clipboard=[moduleFile(p,group.id)];}else clipboard=roots.map(b=>moduleFile(project,b.id));toast(`已复制 ${roots.length} 个模块及内部连接`);}
function paste(){if(!clipboard.length)return toast('请先复制模块',true);const at=center();transact('已粘贴独立副本',()=>{selection=clipboard.map((m,i)=>instantiate(project,m,{x:at.x+i*35,y:at.y+i*35}));if(clipboardGrouped){const id=selection[0];selection=project.blocks.filter(b=>b.parent===id).map(b=>b.id);ungroup(project,id);}});}
function download(data:string|Blob,name:string,type='application/json'){const blob=typeof data==='string'?new Blob([data],{type}):data;const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name.replace(/[<>:"/\\|?*]/g,'_');a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);}
function save(){captureView();download(JSON.stringify(project,null,2),`${project.name}.fpga-diagram.json`);dirty=false;storeDraft();toast('工程文件已导出');}
function saveLibrary(){try{localStorage.setItem(libraryKey,JSON.stringify(library));}catch{toast('模块已加入当前会话，浏览器存储不可用，请导出模块包',true);}renderLibrary();}
function renderLibrary(){const query=$<HTMLInputElement>('#library-search').value.toLowerCase();const entries=library.map((m,i)=>({m,i})).filter(({m})=>m.name.toLowerCase().includes(query));$('#module-library').innerHTML=entries.length?entries.map(({m,i})=>`<div class="module-item"><button data-lib="${i}" title="点击加入画布">▣ ${esc(m.name)}</button><button data-lib-export="${i}" title="导出模块包">↗</button><button data-lib-delete="${i}" title="移出模块库">×</button></div>`).join(''):`<div class="empty-library">${query?'没有匹配的模块':'把常用模块收进这里<br>选中模块 → 保存到我的模块'}</div>`;
  $('#module-library').querySelectorAll<HTMLButtonElement>('[data-lib]').forEach(el=>el.onclick=()=>{const m=library[Number(el.dataset.lib)],at=center();transact('已添加模块副本',()=>{selection=[instantiate(project,m,at)];});});
  $('#module-library').querySelectorAll<HTMLButtonElement>('[data-lib-export]').forEach(el=>el.onclick=()=>{const m=library[Number(el.dataset.libExport)];download(JSON.stringify(m,null,2),`${m.name}.fpga-module.json`);});
  $('#module-library').querySelectorAll<HTMLButtonElement>('[data-lib-delete]').forEach(el=>el.onclick=()=>confirmAction('移出模块库','只移除库中的模板，不影响画布上的实例。',()=>{library.splice(Number(el.dataset.libDelete),1);saveLibrary();}));
}
$('#library-search').addEventListener('input',renderLibrary);
$('#project-name').addEventListener('change',()=>transact('工程名称已更新',()=>project.name=$<HTMLInputElement>('#project-name').value.trim()||'未命名工程'));
$('#file-input').addEventListener('change',async()=>{const file=$<HTMLInputElement>('#file-input').files?.[0];if(!file)return;try{if(file.size>20*1024*1024)throw Error('文件超过 20 MB 限制');const data=parseFile(await file.text());if(fileMode==='open'){if(data.format!=='fpga-diagram')throw Error('请选择工程文件；模块文件请使用“导入模块”');const action=()=>load(data);if(dirty)confirmAction('打开工程','当前未保存的修改将被替换，请先保存需要保留的工程。',action);else action();}else{if(data.format!=='fpga-module')throw Error('请选择模块包文件');library.push(data);saveLibrary();const at=center();transact('模块已导入画布和模块库',()=>selection=[instantiate(project,data,at)]);}}catch(e){fail(e);}finally{$<HTMLInputElement>('#file-input').value='';}});

async function exportImage(format:'svg'|'png',onlySelected:boolean,ratio:number,transparent:boolean){
  let p=clone(project);if(onlySelected){const b=selectedBlock();if(!b)throw Error('请选择单个模块再导出');const m=moduleFile(p,b.id);p.blocks=m.blocks;p.wires=m.wires;}
  if(!p.blocks.length)throw Error('画布为空');
  const host=document.createElement('div');host.style.cssText='position:fixed;left:-20000px;top:0;width:3000px;height:3000px;pointer-events:none';document.body.append(host);
  const exportGraph=new Graph({container:host,width:3000,height:3000,async:false,interacting:false});exportGraph.use(new Export());
  try{renderGraph(exportGraph,p);await document.fonts.ready;const stage=host.querySelector<SVGGElement>('.x6-graph-svg-stage')!;const box=stage.getBBox();const pad=35,viewBox={x:box.x-pad,y:box.y-pad,width:box.width+pad*2,height:box.height+pad*2};
    const svg=await exportGraph.toSVGAsync({viewBox,preserveDimensions:true,copyStyles:false,serializeImages:false,beforeSerialize:(svg)=>{
      svg.querySelectorAll('circle[magnet]').forEach(el=>el.setAttribute('visibility','hidden'));
      svg.querySelectorAll('.x6-edge-wrap,.x6-widget-selection,.x6-widget-transform,.x6-cell-tools').forEach(el=>el.remove());
      if(!transparent){const rect=document.createElementNS('http://www.w3.org/2000/svg','rect');Object.entries({x:viewBox.x,y:viewBox.y,width:viewBox.width,height:viewBox.height,fill:'#ffffff'}).forEach(([k,v])=>rect.setAttribute(k,String(v)));svg.insertBefore(rect,svg.firstChild);}
    }});
    const name=onlySelected?selectedBlock()!.name:project.name;
    if(format==='svg'){download(svg,`${name}.svg`,'image/svg+xml');}
    else{const width=Math.ceil(viewBox.width*ratio),height=Math.ceil(viewBox.height*ratio);if(width>16000||height>16000||width*height>64000000)throw Error('图片尺寸过大，请降低倍率或选择单个模块导出');const url=URL.createObjectURL(new Blob([svg],{type:'image/svg+xml'}));try{const image=new Image();await new Promise<void>((res,rej)=>{image.onload=()=>res();image.onerror=()=>rej(Error('SVG 转 PNG 失败'));image.src=url;});const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;canvas.getContext('2d')!.drawImage(image,0,0,width,height);const blob=await new Promise<Blob>((res,rej)=>canvas.toBlob(b=>b?res(b):rej(Error('PNG 编码失败'))));download(blob,`${name}.png`);}finally{URL.revokeObjectURL(url);}}
    toast('图片已导出');
  }finally{exportGraph.dispose();host.remove();}
}
function exportDialog(){modal('导出图片',`<p>按内容边界导出，自动去除网格与编辑手柄。图像反映当前模块的展开 / 折叠状态。</p><div class="export-options"><div><label>图片格式</label><select id="export-format"><option value="png">PNG · 高清图片</option><option value="svg">SVG · 矢量图形</option></select></div><div><label>导出范围</label><select id="export-scope"><option value="all">整个工程</option><option value="selected" ${selectedBlock()?'':'disabled'}>所选模块</option></select></div><div><label>PNG 分辨率</label><select id="export-ratio"><option value="1">1×</option><option value="2" selected>2×</option><option value="4">4×</option></select></div><div><label>背景</label><select id="export-bg"><option value="white">白色背景</option><option value="transparent">透明背景</option></select></div></div>`,[{text:'取消',action:closeModal},{text:'导出图片',primary:true,action:async()=>{const f=$<HTMLSelectElement>('#export-format').value as 'png'|'svg',s=$<HTMLSelectElement>('#export-scope').value==='selected',r=Number($<HTMLSelectElement>('#export-ratio').value),t=$<HTMLSelectElement>('#export-bg').value==='transparent';await exportImage(f,s,r,t);closeModal();}}]);}
function splitWire(){const w=project.wires.find(w=>w.id===selection[0]);if(!w)return toast('请选择一条连线',true);const view=graph.findViewByCell(w.id) as any;const point=view?.getPointAtRatio(.5)??center();transact('已插入分支连接点',()=>{const j=block(w.name||'signal',point.x-5,point.y-5);j.kind='junction';j.w=j.h=10;j.parent=w.scope;j.ports=[port('signal','inout',resolve(project,w.source).p.width)];project.blocks.push(j);const oldTarget=clone(w.target);w.target={block:j.id,port:j.ports[0].id};w.vertices=[];addConnection(project,w.target,oldTarget,w.name);selection=[j.id];});}
function help(){modal('使用指南',`<div class="help-grid"><section><h3>画图与连接</h3><p>点击左侧元件添加。选中模块后编辑名称、尺寸和端口；拖动端口圆点连线。选中连线后拖动控制点调整路径。</p><h3>层级封装</h3><p>Shift 点击或框选同层模块，然后封装。双击封装模块展开/折叠。选中展开的封装后添加元件，新元件会放入内部。父模块 input 在内部可驱动子模块 input。</p><h3>信号分支</h3><p>输出可连接多个输入；若需要明确的分支黑点，选中连线，点击“插入分支连接点”，再从黑点连接其他端口。交叉线不自动相连。</p></section><section><h3>保存与复用</h3><p>Ctrl+S 下载工程 JSON。选中模块保存到库，或导出模块包。模块每次导入都是独立副本。跨模块的整体复制可先封装。</p><h3>快捷键</h3><p>Ctrl+Z 撤销 · Ctrl+Shift+Z 重做<br>Ctrl+C / V 复制粘贴 · Delete 删除<br>Ctrl+G 封装 · F 适应画布<br>滚轮缩放 · 右键拖动画布</p><h3>连接检查</h3><p>禁止方向冲突、已知位宽不匹配、多输出驱动。表达式不求值，虚线表示待检查；inout 不验证三态时序。此工具用于结构设计，不进行逻辑仿真。</p></section></div>`,[{text:'开始设计',primary:true,action:closeModal}]);}
const actions:Record<string,()=>void>={
  'add-block':()=>addBlock('block'),'add-input':()=>addBlock('input'),'add-output':()=>addBlock('output'),'add-junction':()=>addBlock('junction'),
  new:()=>confirmAction('新建工程','将清空当前画布，请先保存需要保留的工程。',()=>load(emptyProject())),
  open:()=>{fileMode='open';$<HTMLInputElement>('#file-input').click();},'import-module':()=>{fileMode='module';$<HTMLInputElement>('#file-input').click();},save,export:exportDialog,help,
  'example-uart':()=>confirmAction('载入 UART 示例','当前画布将替换为示例工程，请先保存需要保留的设计。',()=>load(uartExample(),true)),
  'example-key':()=>confirmAction('载入按键示例','当前画布将替换为示例工程，请先保存需要保留的设计。',()=>load(keyExample(),true)),
  undo:()=>{if(!history.length)return;future.push(clone(project));project=history.pop()!;selection=[];dirty=true;render();storeDraft();},redo:()=>{if(!future.length)return;history.push(clone(project));project=future.pop()!;selection=[];dirty=true;render();storeDraft();},
  copy,paste,delete:deleteSelection,'edit-ports':editPorts,
  group:()=>{if(!selection.some(id=>project.blocks.some(b=>b.id===id)))return toast('请先选择要封装的模块',true);askName('封装为模块','new_module',name=>transact('已封装，跨边界信号已映射为端口',()=>{const b=groupBlocks(project,selection,name);selection=[b.id];}));},
  collapse:()=>{const b=selectedBlock();if(!b?.composite)return toast('请选择一个封装模块',true);transact('已切换模块视图',()=>toggleCollapse(project,b.id));},
  ungroup:()=>{const b=selectedBlock();if(!b)return;transact('已解除封装，接口映射保留为分支点',()=>{ungroup(project,b.id);selection=[];});},
  'library-add':()=>{const b=selectedBlock();if(!b)return toast('请选择单个模块',true);library.push(moduleFile(project,b.id));saveLibrary();toast('模块已保存到本机模块库');},
  'export-module':()=>{const b=selectedBlock();if(!b)return toast('请选择单个模块',true);download(JSON.stringify(moduleFile(project,b.id),null,2),`${b.name}.fpga-module.json`);toast('模块包已导出');},
  'reset-route':()=>{const w=project.wires.find(w=>w.id===selection[0]);if(w)transact('折线路径已重置',()=>w.vertices=[]);},'split-wire':splitWire,
  align:()=>{const selected=project.blocks.filter(b=>selection.includes(b.id)&&!selection.includes(b.parent??''));if(selected.length<2)return toast('请至少选择两个同层模块',true);if(selected.some(b=>b.parent!==selected[0].parent))return toast('只能对齐同层模块',true);transact('模块已左对齐',()=>{const x=Math.min(...selected.map(b=>b.x));selected.forEach(b=>{const dx=x-b.x,ids=descendants(project,b.id);project.blocks.filter(n=>ids.has(n.id)).forEach(n=>n.x+=dx);project.wires.filter(w=>w.scope&&ids.has(w.scope)).forEach(w=>w.vertices.forEach(v=>v.x+=dx));});});},
  grid:()=>{grid=!grid;graph.setGridSize(grid?10:1);if(grid)graph.showGrid();else graph.hideGrid();$('#grid-toggle').classList.toggle('active',grid);},
  'zoom-in':()=>graph.zoom(.1),'zoom-out':()=>graph.zoom(-.1),fit,
  recover:()=>{if(pendingDraft){try{const p=parseFile(pendingDraft);if(p.format==='fpga-diagram'){project=p;history=[];future=[];selection=[];render();dirty=true;}$('#recovery').hidden=true;pendingDraft=null;}catch(e){fail(e);}}},
  'dismiss-recovery':()=>{$('#recovery').hidden=true;pendingDraft=null;storeDraft();},
};
document.addEventListener('click',e=>{const el=(e.target as HTMLElement).closest<HTMLElement>('[data-action]');if(el){try{actions[el.dataset.action!]?.();}catch(e){fail(e);}}});
document.addEventListener('keydown',e=>{if((e.target as HTMLElement).closest('input,textarea,select')||$<HTMLDialogElement>('#modal').open)return;const ctrl=e.ctrlKey||e.metaKey;let action:string|undefined;if(ctrl){action=({s:'save',z:e.shiftKey?'redo':'undo',y:'redo',c:'copy',v:'paste',g:'group'} as Record<string,string>)[e.key.toLowerCase()];}else if(e.key==='Delete'||e.key==='Backspace')action='delete';else if(e.key.toLowerCase()==='f')action='fit';if(action){e.preventDefault();try{actions[action]();}catch(e){fail(e);}}});
window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue='';}});
window.addEventListener('pagehide',()=>{if(!pendingDraft){try{captureView();localStorage.setItem(draftKey,JSON.stringify(project));}catch{/* Downloads remain the durable backup. */}}});
render();renderLibrary();requestAnimationFrame(()=>{fit();if(pendingDraft)$('#recovery').hidden=false;});
