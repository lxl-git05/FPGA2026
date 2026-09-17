import { addConnection, block, emptyProject, endpoint, groupBlocks, port, type Block, type Project } from './model';
export function terminal(name: string, kind: 'input' | 'output', x: number, y: number, width = '1'): Block {
  const b = block(name, x, y); b.kind = kind; b.w = 125; b.h = 36; b.fontSize = 17; b.ports = [port(name, kind === 'input' ? 'output' : 'input', width)]; return b;
}
export function keyExample(): Project {
  const p = emptyProject('按键消抖 · key_filter'), b = block('key_filter', 380, 220);
  b.w = 270; b.h = 210; b.fontSize = 28; b.ports = [port('clk','input'), port('reset_n','input'), port('key_in','input'), port('key_flag','output'), port('key_state','output')]; p.blocks.push(b);
  b.ports.forEach((pt, i) => { const input = pt.direction === 'input', y = input ? 270 + i * 55 : 285 + (i - 3) * 80; pt.offset = (y - b.y) / b.h; const t = terminal(pt.name, input ? 'input' : 'output', input ? 100 : 805, y - 18); p.blocks.push(t); addConnection(p, input ? endpoint(t,pt.name) : endpoint(b,pt.name), input ? endpoint(b,pt.name) : endpoint(t,pt.name)); });
  return p;
}
export function uartExample(): Project {
  const p = emptyProject('UART 发送系统');
  const f = block('FSM',340,360); f.w = 155; f.h = 195; f.ports = [port('clk','input'),port('rst_n','input'),port('send_en','input'),port('data','input','8'),port('byte_tx_done','input'),port('byte_send_en','output'),port('data_byte','output','8'),port('Tx_Done','output')];
  const tx = block('uart_byte_tx',645,200); tx.w = 255; tx.h = 290; tx.fontSize = 25; tx.ports = [port('clk','input'),port('rst_n','input'),port('Baud_Set','input','3'),port('byte_send_en','input'),port('data_byte','input','8'),port('uart_tx','output'),port('uart_state','output'),port('byte_tx_done','output')];
  p.blocks.push(f,tx);
  addConnection(p,endpoint(f,'byte_send_en'),endpoint(tx,'byte_send_en'),'byte_send_en');
  addConnection(p,endpoint(f,'data_byte'),endpoint(tx,'data_byte'),'data_byte[7:0]');
  const feedback = addConnection(p,endpoint(tx,'byte_tx_done'),endpoint(f,'byte_tx_done'),'byte_tx_done'); feedback.vertices = [{x:950,y:510},{x:300,y:510}];
  const inputs: [string,string,number][] = [['clk','1',155],['rst_n','1',225],['Baud_Set','3',295],['send_en','1',425],['data','8',500]];
  inputs.forEach(([name,width,y]) => { const t = terminal(name,'input',60,y,width);p.blocks.push(t); for (const b of [f,tx]) if (b.ports.some(pt => pt.name === name)) addConnection(p,endpoint(t,name),endpoint(b,name)); });
  [['uart_tx',tx,235],['uart_state',tx,335],['Tx_Done',f,520]].forEach(([name,b,y]) => { const t = terminal(name as string,'output',1090,y as number);p.blocks.push(t);addConnection(p,endpoint(b as Block,name as string),endpoint(t,name as string)); });
  const g = groupBlocks(p,[f.id,tx.id],'uart_data_tx'); g.note = 'UART 发送控制：FSM 调度单字节发送模块。支持展开、折叠与模块包复用。';
  g.x=260;g.y=100;g.w=900;g.h=670;g.fontSize=28;
  f.x=420;f.y=430;f.w=180;f.h=260;f.fontSize=28;
  tx.x=830;tx.y=220;tx.w=240;tx.h=370;tx.fontSize=28;
  const positions = (b:Block, ys:Record<string,number>) => b.ports.forEach(pt=>{pt.offset=(ys[pt.name]-b.y)/b.h;});
  positions(g,{clk:260,rst_n:310,Baud_Set:360,send_en:555,data:615,uart_tx:270,uart_state:340,Tx_Done:740});
  positions(f,{clk:465,rst_n:505,send_en:555,data:615,byte_tx_done:665,byte_send_en:555,data_byte:615,Tx_Done:665});
  positions(tx,{clk:260,rst_n:310,Baud_Set:360,byte_send_en:435,data_byte:505,uart_tx:270,uart_state:340,byte_tx_done:560});
  const topY:Record<string,number>={clk:260,rst_n:310,Baud_Set:360,send_en:555,data:615,uart_tx:270,uart_state:340,Tx_Done:740};
  p.blocks.filter(b=>b.kind==='input'||b.kind==='output').forEach(b=>{b.x=b.kind==='input'?40:1270;b.y=topY[b.name]-18;});
  p.wires.forEach(w=>{w.vertices=[];if(w.name==='byte_send_en'){w.name='';w.vertices=[{x:690,y:555},{x:690,y:435}];}if(w.name==='data_byte[7:0]'){w.name='';w.vertices=[{x:740,y:615},{x:740,y:505}];}if(w.name==='byte_tx_done'){w.name='';w.vertices=[{x:1110,y:560},{x:1110,y:715},{x:365,y:715},{x:365,y:665}];}if(w.source.block===f.id&&w.target.block===g.id){w.vertices=[{x:650,y:665},{x:650,y:740}];}});
  // Explicit clock/reset branch dots make shared signals unambiguous.
  for(const [name,x] of [['clk',320],['rst_n',345]] as const){
    const j=block(name,x-5,topY[name]-5);j.kind='junction';j.w=j.h=10;j.parent=g.id;j.ports=[port(name,'inout')];p.blocks.push(j);
    p.wires.filter(w=>w.scope===g.id&&w.source.block===g.id&&w.source.port===endpoint(g,name).port).forEach(w=>{w.source=endpoint(j,name);if(w.target.block===f.id){const y=name==='clk'?465:505;w.vertices=[{x,y}];}});
    addConnection(p,endpoint(g,name),endpoint(j,name));
  }
  return p;
}
