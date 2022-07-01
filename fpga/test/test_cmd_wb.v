`timescale 1 ns/10 ps  // time-unit = 1 ns, precision = 10 ps

module stream_gen (
    input i_clk,
    input i_enable,

    input i_ready,
    output [7:0] o_data,
    output o_valid
);

    reg [7:0] d;

    assign o_valid = i_enable;
    assign o_data = d;

    initial begin
        d <= 8'd0;
    end

    always @(posedge i_clk) begin
        if (o_valid && i_ready) begin
            // Transaction happens, increment data
            d <= d + 8'd1;
        end
    end

endmodule

module test_cmd_wb;

    localparam WB_ADDR_WIDTH = 6;

    `include "cmd_defines.vh"
    `include "mreq_defines.vh"

    wb_mem_dly #(
        .WB_ADDR_WIDTH(WB_ADDR_WIDTH),
        .STALL_WS(0),
        .ACK_WS(0)
    ) mem (
        .i_clk(clk),
        .i_rst(rst),
        // wb
        .i_wb_cyc(wb_cyc),
        .i_wb_stb(wb_stb),
        .o_wb_stall(wb_stall),
        .o_wb_ack(wb_ack),
        .i_wb_we(wb_we),
        .i_wb_addr(wb_addr),
        .i_wb_data(wb_data_w),
        .i_wb_sel(wb_sel),
        .o_wb_data(wb_data_r)
    );

    // wb_dummy dummy (
    //     .i_clk(clk),
    //     // wb
    //     .i_wb_cyc(wb_cyc),
    //     .i_wb_stb(wb_stb),
    //     .o_wb_stall(wb_stall),
    //     .o_wb_ack(wb_ack),
    //     .o_wb_data(wb_data_r)
    // );

    stream_gen rx_stream (
        .i_clk(clk),
        .i_enable(1'b1),
        .i_ready(rx_ready),
        .o_data(rx_data),
        .o_valid(rx_valid)
    );

    cmd_wb #(
        .WB_ADDR_WIDTH(WB_ADDR_WIDTH)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        // wb
        .o_wb_cyc(wb_cyc),
        .o_wb_stb(wb_stb),
        .i_wb_stall(wb_stall),
        .i_wb_ack(wb_ack),
        .o_wb_we(wb_we),
        .o_wb_addr(wb_addr),
        .o_wb_data(wb_data_w),
        .o_wb_sel(wb_sel),
        .i_wb_data(wb_data_r),
        // mreq
        .i_mreq_valid(mreq_valid),
        .o_mreq_ready(mreq_ready),
        .i_mreq(mreq),
        // rx
        .o_rx_ready(rx_ready),
        .i_rx_data(rx_data),
        .i_rx_valid(rx_valid),
        // tx
        .i_tx_ready(tx_ready),
        .o_tx_data(tx_data),
        .o_tx_valid(tx_valid)
    );

    reg clk = 0;
    reg rst = 0;
    // wb
    wire wb_cyc;
    wire wb_stb;
    wire wb_stall;
    wire wb_ack;
    wire wb_we;
    wire [WB_ADDR_WIDTH-1:0] wb_addr;
    wire [31:0] wb_data_w;
    wire [3:0] wb_sel;
    wire [31:0] wb_data_r;
    // mreq control
    reg mreq_valid = 0;
    wire mreq_ready;
    // mreq descriptor
    reg [MREQ_NBIT-1:0] mreq = 0;
    reg [7:0] mreq_tag = 0;
    reg mreq_wr = 0;
    reg mreq_aincr = 0;
    reg [2:0] mreq_wfmt = 0;
    reg [7:0] mreq_wcnt = 0;
    reg [23:0] mreq_addr = 0;
    // rx stream
    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_ready;
    // tx stream
    wire [7:0] tx_data;
    wire tx_valid;
    reg tx_ready = 0;

    always #5 clk = ~clk;

    reg mreq_ready_past = 0;
    always @(posedge clk) begin
        mreq_ready_past <= mreq_ready;
        if (rx_valid && rx_ready) begin
            $display("Rx: CMD_WB consumed byte 0x%02x", rx_data);
        end
        if (tx_valid && tx_ready) begin
            $display("Tx: CMD_WB produced byte 0x%02x", tx_data);
        end
        if (mreq_valid && mreq_ready) begin
            unpack_mreq(
                mreq,
                mreq_tag, mreq_wr, mreq_aincr, mreq_wfmt, mreq_wcnt, mreq_addr
            );
            $display("MREQ: CMD_WB acknowledged request: tag=%02x wr=%b aincr=%b wfmt=%03b wcnt=%03d addr=0x%08x",
                mreq_tag,
                mreq_wr,
                mreq_aincr,
                mreq_wfmt,
                mreq_wcnt,
                mreq_addr
            );
        end
    end

    initial begin
        $dumpfile("test_cmd_wb.vcd");
        $dumpvars(0);


        rst <= 1;
        @(posedge clk);
        rst <= 0;

        // --REQ-- Write something
        mreq <= pack_mreq(
            8'hAA,              // tag
            1,                  // wr
            1,                  // aincr
            MREQ_WFMT_32S0,     // wfmt
            8'd3,               // wcnt
            23'h000003,         // addr
        );

        mreq_valid <= 1'b1;
        @(posedge clk); wait(mreq_ready) @(posedge clk);
        mreq_valid <= 1'b0;

        // --REQ-- Write something
        mreq <= pack_mreq(
            8'hCC,              // tag
            1,                  // wr
            1,                  // aincr
            MREQ_WFMT_16S0,     // wfmt
            8'd3,               // wcnt
            23'h000007,         // addr
        );

        mreq_valid <= 1'b1;
        @(posedge clk); wait(mreq_ready) @(posedge clk);
        mreq_valid <= 1'b0;

        // --REQ-- Write something
        mreq <= pack_mreq(
            8'hCC,              // tag
            1,                  // wr
            1,                  // aincr
            MREQ_WFMT_8S2,      // wfmt
            8'd3,               // wcnt
            23'h000007,         // addr
        );

        mreq_valid <= 1'b1;
        @(posedge clk); wait(mreq_ready) @(posedge clk);
        mreq_valid <= 1'b0;

        // --REQ-- Read something
        mreq <= pack_mreq(
            8'hCC,              // tag
            0,                  // wr
            1,                  // aincr
            MREQ_WFMT_8S0,      // wfmt
            8'd3,               // wcnt
            23'h000003,         // addr
        );

        mreq_valid <= 1'b1;

        repeat (10) @(posedge clk);
        // unblock tx
        tx_ready <= 1'b1;
        @(posedge clk); wait(mreq_ready) @(posedge clk);
        mreq_valid <= 1'b0;

        repeat(10) @(posedge clk);

        // --REQ-- Read something
        mreq <= pack_mreq(
            8'hCC,              // tag
            0,                  // wr
            1,                  // aincr
            MREQ_WFMT_16S0,     // wfmt
            8'd15,              // wcnt
            23'h000000,         // addr
        );

        mreq_valid <= 1'b1;
        @(posedge clk); wait(mreq_ready) @(posedge clk);
        mreq_valid <= 1'b0;

        repeat(10) @(posedge clk);

        // --REQ-- Read something
        mreq <= pack_mreq(
            8'hCC,              // tag
            0,                  // wr
            1,                  // aincr
            MREQ_WFMT_8S2,      // wfmt
            8'd15,              // wcnt
            23'h000000,         // addr
        );

        mreq_valid <= 1'b1;
        @(posedge clk); wait(mreq_ready) @(posedge clk);
        mreq_valid <= 1'b0;

        repeat (20) @(posedge clk);



        $finish;
    end

endmodule
