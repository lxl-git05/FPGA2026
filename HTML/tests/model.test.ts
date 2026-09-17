import test from 'node:test';
import assert from 'node:assert/strict';
import { addConnection, block, clone, descendants, emptyProject, endpoint, fitContainers, groupBlocks, instantiate, key, moduleFile, netComponents, parseFile, port, toggleCollapse, ungroup, validate, visible } from '../src/model';
import { keyExample, uartExample } from '../src/examples';

test('示例工程与文件往返保留端口、映射及折线',()=>{
  for(const p of [keyExample(),uartExample()]){
    assert.deepEqual(validate(p),[]);
    const normalized=clone(p);normalized.blocks.forEach(b=>{b.composite=!!b.composite;b.collapsed=!!b.collapsed;});
    assert.deepEqual(JSON.parse(JSON.stringify(parseFile(JSON.stringify(p)))),JSON.parse(JSON.stringify(normalized)));
  }
});
test('拒绝方向冲突、已知位宽冲突及重复连接，允许扇出和反馈',()=>{
  const p=emptyProject(),a=block('a'),b=block('b'),c=block('c');p.blocks.push(a,b,c);
  assert.throws(()=>addConnection(p,endpoint(a,'clk'),endpoint(b,'clk')),/方向/);
  assert.throws(()=>addConnection(p,endpoint(a,'data'),endpoint(b,'clk')),/位宽/);
  b.ports.push(port('din','input','8'));c.ports.push(port('din','input','[7:0]'));
  addConnection(p,endpoint(a,'data'),endpoint(b,'din'));addConnection(p,endpoint(a,'data'),endpoint(c,'din'));
  assert.throws(()=>addConnection(p,endpoint(a,'data'),endpoint(b,'din')),/已经连接/);
  a.ports.push(port('feedback','input','8'));addConnection(p,endpoint(b,'data'),endpoint(a,'feedback'));assert.deepEqual(validate(p),[]);
});
test('符号位宽允许连接但产生提示；两个驱动经分支汇合仍被拒绝',()=>{
  const p=emptyProject(),a=block('a'),b=block('b'),j=block('j');j.kind='junction';j.ports=[port('net','inout','DATA_WIDTH')];p.blocks.push(a,b,j);
  addConnection(p,endpoint(a,'data'),endpoint(j,'net'));assert.match(validate(p)[0],/符号/);
  assert.throws(()=>addConnection(p,endpoint(b,'data'),endpoint(j,'net')),/多个输出/);
});
test('三层封装、折叠恢复及跨层拒绝',()=>{
  const p=uartExample(),g=p.blocks.find(b=>b.composite)!;
  const layout=clone(p.blocks.filter(b=>b.parent===g.id));
  toggleCollapse(p,g.id);assert.equal(p.blocks.filter(b=>b.parent===g.id).every(b=>!visible(p,b)),true);
  toggleCollapse(p,g.id);assert.deepEqual(p.blocks.filter(b=>b.parent===g.id),layout);
  const outer=groupBlocks(p,[g.id],'outer');groupBlocks(p,[outer.id],'top');validate(p);
  const leaf=p.blocks.find(b=>b.name==='FSM')!,input=p.blocks.find(b=>b.kind==='input')!;
  assert.throws(()=>addConnection(p,endpoint(input,'clk'),endpoint(leaf,'clk')),/跨层/);
});
test('父模块输入在内部可扇出，解除封装保留网络连通性',()=>{
  const p=uartExample(),g=p.blocks.find(b=>b.composite)!;
  const input=p.blocks.find(b=>b.kind==='input'&&b.name==='clk')!,f=p.blocks.find(b=>b.name==='FSM')!,tx=p.blocks.find(b=>b.name==='uart_byte_tx')!;
  const check=()=>{const nets=netComponents(p);assert.equal(nets.get(key(endpoint(input,'clk'))),nets.get(key(endpoint(f,'clk'))));assert.equal(nets.get(key(endpoint(f,'clk'))),nets.get(key(endpoint(tx,'clk'))));};
  check();ungroup(p,g.id);validate(p);check();
});
test('重复导入完整封装为独立副本，不保留外部连线',()=>{
  const p=uartExample(),root=p.blocks.find(b=>b.composite)!,m=moduleFile(p,root.id),dest=emptyProject();
  const decoded=parseFile(JSON.stringify(m));assert.equal(decoded.format,'fpga-module');
  const a=instantiate(dest,m,{x:0,y:0}),b=instantiate(dest,m,{x:1000,y:0});
  const aa=descendants(dest,a),bb=descendants(dest,b);assert.ok([...aa].every(id=>!bb.has(id)));assert.equal(dest.wires.length,m.wires.length*2);
  dest.blocks.find(n=>n.id===a)!.name='changed';assert.notEqual(dest.blocks.find(n=>n.id===b)!.name,'changed');validate(dest);
});
test('恶意或损坏文件被拒绝，标注作为文本保存',()=>{
  const p=keyExample();p.blocks[0].name='<img src=x onerror=alert(1)>';assert.equal(parseFile(JSON.stringify(p)).blocks[0].name,p.blocks[0].name);
  assert.throws(()=>parseFile(JSON.stringify({...p,schemaVersion:99})),/版本/);
  const broken=clone(p);broken.wires[0].source.port='missing';assert.throws(()=>parseFile(JSON.stringify(broken)),/不存在/);
  const cyclic=clone(p);cyclic.blocks[0].composite=true;cyclic.blocks[0].parent=cyclic.blocks[0].id;assert.throws(()=>parseFile(JSON.stringify(cyclic)),/循环/);
});
test('已连接端口重命名不改变端点 ID；改变位宽会被拒绝',()=>{
  const p=keyExample(),before=clone(p.wires);p.blocks[0].ports[0].name='clock_in';assert.deepEqual(p.wires,before);validate(p);
  p.blocks[0].ports[0].width='8';assert.throws(()=>validate(p),/位宽/);
});
test('空壳封装的输出仍参与多驱动检查',()=>{
  const p=emptyProject(),a=block('a'),b=block('b'),j=block('net');a.composite=true;b.composite=true;j.kind='junction';j.ports=[port('net','inout','8')];p.blocks.push(a,b,j);
  addConnection(p,endpoint(a,'data'),endpoint(j,'net'));assert.throws(()=>addConnection(p,endpoint(b,'data'),endpoint(j,'net')),/多个输出/);
});
test('内部模块超出边框时自动扩展容器，不改变内部坐标',()=>{
  const p=uartExample(),g=p.blocks.find(b=>b.composite)!,f=p.blocks.find(b=>b.name==='FSM')!;f.x=g.x-100;f.y=g.y-80;
  const before={x:f.x,y:f.y};fitContainers(p);assert.deepEqual({x:f.x,y:f.y},before);assert.ok(g.x<f.x&&g.y<f.y);validate(p);
});
