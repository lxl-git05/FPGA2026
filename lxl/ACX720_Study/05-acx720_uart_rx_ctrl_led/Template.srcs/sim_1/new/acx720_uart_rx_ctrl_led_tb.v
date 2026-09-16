`timescale 1ns / 1ps
module acx720_uart_rx_ctrl_led_tb;
    // 1. 例化RX_cmd
    //Ports
    reg  clk;
    reg  rst_n;
    reg uart_rx;
    wire LED ;

    parameter Baud_Set = 3'd0; 

    acx720_uart_rx_ctrl_led  acx720_uart_rx_ctrl_led_inst (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .LED(LED)
    );

    // 2. 逻辑
    // 2.1 时钟
    initial clk = 0 ;
    always #10 clk = ~clk ;

    // 2.2 串口发送
    wire [19:0] delay_time;
    assign delay_time = (Baud_Set == 3'd0) ? 20'd104166: 
                        (Baud_Set == 3'd1) ? 20'd52083: 
                        (Baud_Set == 3'd2) ? 20'd26041: 
                        (Baud_Set == 3'd3) ? 20'd17361: 
                                              20'd8680; 
    task uart_tx_byte; 
        input [7:0]tx_data; 
        begin 
            uart_rx = 1; 
            #20; 
            uart_rx = 0; 
            #delay_time; 
            uart_rx = tx_data[0]; // 串口发送是LSB
            #delay_time; 
            uart_rx = tx_data[1]; 
            #delay_time; 
            uart_rx = tx_data[2]; 
            #delay_time; 
            uart_rx = tx_data[3]; 
            #delay_time; 
            uart_rx = tx_data[4]; 
            #delay_time; 
            uart_rx = tx_data[5]; 
            #delay_time; 
            uart_rx = tx_data[6]; 
            #delay_time; 
            uart_rx = tx_data[7]; 
            #delay_time; 
            uart_rx = 1; 
            #delay_time;          
        end 
    endtask

    // 2.3 逻辑检测
    initial begin 
        rst_n = 0; 
        uart_rx = 1; 
        #201; 
        rst_n = 1; 
        #200;  
        // 正确数据
        uart_tx_byte(8'h55); 
        #(delay_time*10); 
        uart_tx_byte(8'ha5); 
        #(delay_time*10); 
        uart_tx_byte(8'h55); 
        #(delay_time*10); 
        uart_tx_byte(8'ha5); 
        #(delay_time*10); 
        uart_tx_byte(8'h00); 
        #(delay_time*10); 
        uart_tx_byte(8'h00); 
        #(delay_time*10); 
        uart_tx_byte(8'hc3); 
        #(delay_time*10); 
        uart_tx_byte(8'h50); 
        #(delay_time*10);   
        uart_tx_byte(8'hA3); 
        #(delay_time*10);        
        uart_tx_byte(8'hf0); 
        #(delay_time*10);
        // 错误数据
        uart_tx_byte(8'h55); 
        #(delay_time*10); 
        uart_tx_byte(8'ha2);    // 错误数据
        #(delay_time*10); 
        uart_tx_byte(8'h55); 
        #(delay_time*10); 
        uart_tx_byte(8'ha5); 
        #(delay_time*10); 
        uart_tx_byte(8'h00); 
        #(delay_time*10); 
        uart_tx_byte(8'h00); 
        #(delay_time*10); 
        uart_tx_byte(8'hc3); 
        #(delay_time*10); 
        uart_tx_byte(8'h50); 
        #(delay_time*10);   
        uart_tx_byte(8'hAA); 
        #(delay_time*10);        
        uart_tx_byte(8'hf0); 
        #(delay_time*10);
        $stop;
    end
     
endmodule
