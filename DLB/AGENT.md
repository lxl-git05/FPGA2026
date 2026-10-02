+ 不要随意新建.v
+ 需要上板测试的模块都写在test，我自己会随后进行上板测试

- 串口波特率默认使用 `.Baud_Set(3'd4)`，即 115200，除非另有指定。
- 模块例化采用以下换行格式：模块名及参数一行，实例名另起一行，每个端口独占一行；未使用的输出显式留空。
- 代码保持简洁，在初始化、关键事件处理和接口配置处添加少量说明性注释。

```verilog
uart_data_tx #(.DATA_WIDTH(DATA_WIDTH))
    uart_data_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data(data),
        .send_en(send_en),
        .Baud_Set(3'd4),
        .uart_tx(uart_tx),
        .Tx_Done(),
        .uart_state()
    );
```