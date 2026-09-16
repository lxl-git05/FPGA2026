// 项目4:单字节串口接收
`timescale 1ns / 1ps
module uart_byte_rx
    (
        input wire clk,
        input wire rst_n,
        input wire [2:0] baud_set,  // 波特率设置
        input wire uart_rx,
        output reg rx_done,
        output reg [7:0] data_byte  // 输出数据      
    );

    // 比较重要的信号
    reg uart_state ;   // 接收数据状态

    // 1. 串口输入数据异步->同步,采用双触发器防止亚稳态
    reg uart_rx_sync1 ;
    reg uart_rx_sync2 ;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rx_sync1 <= 1'b0 ;
            uart_rx_sync2 <= 1'b0 ;
        end
        else begin
            uart_rx_sync1 <= uart_rx ;
            uart_rx_sync2 <= uart_rx_sync1 ;
        end
    end

    // 2. 边沿检测,也就是检测串口rx的下降沿(空闲->准备开始接收数据)
    wire uart_rx_nedge ;    // 下降沿
    reg uart_rx_reg1 ;      // 输入bit记录触发器
    reg uart_rx_reg2 ;      // 输入bit记录触发器

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rx_reg1 <= 1'b0 ;
            uart_rx_reg2 <= 1'b0 ;
        end
        else begin
            uart_rx_reg1 <= uart_rx_sync2 ;
            uart_rx_reg2 <= uart_rx_reg1 ;
        end
    end

    assign uart_rx_nedge = (!uart_rx_reg1 & uart_rx_reg2) ;

    // 3. 采样时钟选择:实际的采样频率是波特率的16倍
    reg [15:0] bps_DR ;     // 采样时钟ARR(波特率的16倍)
    always@(posedge clk or negedge rst_n)
    if(!rst_n) 
        bps_DR <= 16'd324; 
    else begin 
        case(baud_set) 
            0:bps_DR <= 16'd324; 
            1:bps_DR <= 16'd162; 
            2:bps_DR <= 16'd80; 
            3:bps_DR <= 16'd53; 
            4:bps_DR <= 16'd26; 
            default:bps_DR <= 16'd324;           
        endcase 
    end  

    // 4. 产生采样时钟
    reg [15:0] div_cnt ;
    reg        bps_clk ;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            div_cnt <= 16'b0 ;
        else if (uart_state) begin
            if (div_cnt == bps_DR)
                div_cnt <= 16'd0 ;
            else
                div_cnt <= div_cnt + 1'b1 ;
        end
        else begin
            div_cnt <= 16'd0 ;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            bps_clk <= 1'b0 ;
        else if (div_cnt == bps_DR)
            bps_clk <= 1'b1 ;
        else
            bps_clk <= 1'b0 ;
    end

    // 5. 采样时钟计数器
    reg [7:0] bps_cnt ; // 计数这是一次RX的第几次采样
    reg [2:0] START_BIT ;
    reg [2:0]  STOP_BIT ;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            bps_cnt <= 8'd0 ;
        else if (bps_cnt == 8'd159 | (bps_cnt == 8'd12 && (START_BIT > 2)))     // 起始位6次采样有3次及以上HIGH,作为噪声
            bps_cnt <= 8'd0 ;   // 起始位噪声重置
        else if (bps_clk)
            bps_cnt <= bps_cnt + 1'b1 ;
        else
            bps_cnt <= bps_cnt ;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            rx_done <= 1'd0 ;
        else if (bps_cnt == 8'd159)
            rx_done <= 1'b1 ;
        else
            rx_done <= 1'd0 ;
    end

    // 6. 采样数据接收模块
    reg [2:0] data_byte_pre [0:7];  // [2:0]的信号,一共有0-7一共8个
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            START_BIT <= 3'd0 ;
            STOP_BIT  <= 3'd0 ;
            data_byte_pre[0] <= 3'd0 ;
            data_byte_pre[1] <= 3'd0 ;
            data_byte_pre[2] <= 3'd0 ;
            data_byte_pre[3] <= 3'd0 ;
            data_byte_pre[4] <= 3'd0 ;
            data_byte_pre[5] <= 3'd0 ;
            data_byte_pre[6] <= 3'd0 ;
            data_byte_pre[7] <= 3'd0 ;
        end
        else if (bps_clk)
        begin 
            case (bps_cnt)
                0 : 
                begin
                    START_BIT <= 3'd0 ;
                    STOP_BIT  <= 3'd0 ;
                    data_byte_pre[0] <= 3'd0 ;
                    data_byte_pre[1] <= 3'd0 ;
                    data_byte_pre[2] <= 3'd0 ;
                    data_byte_pre[3] <= 3'd0 ;
                    data_byte_pre[4] <= 3'd0 ;
                    data_byte_pre[5] <= 3'd0 ;
                    data_byte_pre[6] <= 3'd0 ;
                    data_byte_pre[7] <= 3'd0 ;
                end
                6,7,8,9,10,11: START_BIT <= START_BIT + uart_rx_sync2 ;
                22,23,24,25,26,27:data_byte_pre[0] <= data_byte_pre[0] + uart_rx_sync2; 
                38,39,40,41,42,43:data_byte_pre[1] <= data_byte_pre[1] + uart_rx_sync2;  
                54,55,56,57,58,59:data_byte_pre[2] <= data_byte_pre[2] + uart_rx_sync2;  
                70,71,72,73,74,75:data_byte_pre[3] <= data_byte_pre[3] + uart_rx_sync2;  
                86,87,88,89,90,91:data_byte_pre[4] <= data_byte_pre[4] + uart_rx_sync2;  
                102,103,104,105,106,107:data_byte_pre[5] <= data_byte_pre[5] + uart_rx_sync2;  
                118,119,120,121,122,123:data_byte_pre[6] <= data_byte_pre[6] + uart_rx_sync2;  
                134,135,136,137,138,139:data_byte_pre[7] <= data_byte_pre[7] + uart_rx_sync2;  
                150,151,152,153,154,155:STOP_BIT <= STOP_BIT + uart_rx_sync2; 
                default: 
                begin
                    START_BIT <= START_BIT ;
                    STOP_BIT  <= STOP_BIT ;
                    data_byte_pre[0] <= data_byte_pre[0] ;
                    data_byte_pre[1] <= data_byte_pre[1] ;
                    data_byte_pre[2] <= data_byte_pre[2] ;
                    data_byte_pre[3] <= data_byte_pre[3] ;
                    data_byte_pre[4] <= data_byte_pre[4] ;
                    data_byte_pre[5] <= data_byte_pre[5] ;
                    data_byte_pre[6] <= data_byte_pre[6] ;
                    data_byte_pre[7] <= data_byte_pre[7] ;
                end
            endcase            
        end
    end

    // 7. 数据状态判定:输出数据data_byte
    always@(posedge clk or negedge rst_n) 
    if(!rst_n) 
        data_byte <= 8'd0; 
    else if(bps_cnt == 8'd159)begin 
        data_byte[0] <= data_byte_pre[0][2]; 
        data_byte[1] <= data_byte_pre[1][2]; 
        data_byte[2] <= data_byte_pre[2][2]; 
        data_byte[3] <= data_byte_pre[3][2]; 
        data_byte[4] <= data_byte_pre[4][2]; 
        data_byte[5] <= data_byte_pre[5][2]; 
        data_byte[6] <= data_byte_pre[6][2]; 
        data_byte[7] <= data_byte_pre[7][2]; 
    end

    // 8. uart_state标志位: 开始接收数据的时候是1,其他时候是0
    always@(posedge clk or negedge rst_n) 
    if(!rst_n)
		uart_state <= 1'b0;
	else if(uart_rx_nedge)
		uart_state <= 1'b1;
	else if(rx_done || (bps_cnt == 8'd12 && (START_BIT > 2)) || (bps_cnt == 8'd155 && (STOP_BIT < 3)))
		uart_state <= 1'b0;
	else
		uart_state <= uart_state;	

endmodule
