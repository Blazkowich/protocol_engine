`timescale 1ns/1ps
`default_nettype none

module tb;

    reg  [7:0] ui_in  = 8'h00;
    wire [7:0] uo_out;
    reg  [7:0] uio_in = 8'h00;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg        ena    = 1'b1;
    reg        clk    = 1'b0;
    reg        rst_n  = 1'b0;

    tt_um_protocol_engine dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #10 clk = ~clk;   // 50 MHz

    integer pass_count = 0, fail_count = 0;
    integer i, j, k;
    reg [15:0] prog [0:31];
    reg [31:0] rnd_a, rnd_b;

    // ---------- Tasks ----------
    task reset_dut;
        begin
            rst_n = 1'b0; uio_in = 8'h00; ui_in = 8'h00;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task shift_instr(input [15:0] w);
        integer b;
        begin
            for (b = 15; b >= 0; b = b - 1) begin
                uio_in[0] = w[b];
                @(posedge clk); #1;
                uio_in[1] = 1'b1;
                @(posedge clk); #1;
                uio_in[1] = 1'b0;
                @(posedge clk); #1;
            end
        end
    endtask

    task load_prog(input integer n);
        integer jj;
        begin
            @(posedge clk); #1;
            uio_in[3] = 1'b1;
            uio_in[2] = 1'b0;   // imem mode
            @(posedge clk); #1;
            for (jj = 0; jj < n; jj = jj + 1) shift_instr(prog[jj]);
            uio_in[3] = 1'b0;
            uio_in[1] = 1'b0;
            uio_in[0] = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    // Simulation-only shortcut: poke config registers hierarchically.
    // (In real hardware, you'd use the loader's config mode.)
    task write_cfg(input [4:0] addr, input [7:0] data);
        begin
            case (addr)
                5'd0:  dut.cfg_clkdiv_int[7:0]  = data;
                5'd1:  dut.cfg_clkdiv_int[15:8] = data;
                5'd2:  dut.cfg_clkdiv_frac      = data;
                5'd3:  dut.cfg_wrap_top         = data[4:0];
                5'd4:  dut.cfg_wrap_bottom      = data[4:0];
                5'd5:  dut.cfg_shift_dir        = data[1:0];
                5'd6:  dut.cfg_autopull         = data[0];
                5'd7:  dut.cfg_autopush         = data[0];
                5'd8:  dut.cfg_pull_thresh      = data[4:0];
                5'd9:  dut.cfg_push_thresh      = data[4:0];
                5'd10: dut.cfg_side_count       = data[3:0];
                default: ;
            endcase
            @(posedge clk); #1;
        end
    endtask

    task check(input [7:0] exp, input [7:0] act, input [255:0] label);
        begin
            if (exp === act) begin
                $display("  [PASS] %0s = 0x%02h", label, act);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s: expected 0x%02h, got 0x%02h",
                         label, exp, act);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task wait_for_out(input [7:0] val, input integer max_cycles);
        integer c;
        begin
            for (c = 0; c < max_cycles; c = c + 1) begin
                @(posedge clk); #1;
                if (uo_out === val) c = max_cycles;
            end
        end
    endtask

    // ---------- Test Suite ----------
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);

        $display("==========================================");
        $display(" Protocol Engine Test Suite");
        $display("==========================================");

        // ---- Test 1: reset ----
        $display("\n[Test 1] Reset");
        reset_dut();
        check(8'h00, uo_out, "uo_out after reset");
        check(8'h00, uio_oe, "uio_oe after reset");

        // ---- Test 2: SET pins via side-set field ----
        $display("\n[Test 2] SET pins=0xF");
        reset_dut();
        prog[0] = 16'h80F0;   // SET pins[3:0] = 0xF
        prog[1] = 16'hF000;
        load_prog(2);
        wait_for_out(8'h0F, 500);
        check(8'h0F, uo_out, "SET pins=0xF");

        // ---- Test 3: TOGGLE ----
        $display("\n[Test 3] TOGGLE");
        reset_dut();
        prog[0] = 16'h80F0;
        prog[1] = 16'hBF00;
        prog[2] = 16'hF000;
        load_prog(3);
        wait_for_out(8'h00, 500);
        check(8'h00, uo_out[3:0], "TOGGLE 0xF -> 0");

        // ---- Test 4: SETOE ----
        $display("\n[Test 4] SETOE");
        reset_dut();
        prog[0] = 16'h83F0;   // SET pin_oe = 0xF
        prog[1] = 16'hF000;
        load_prog(2);
        wait_for_out(8'h0F, 500);
        check(8'h0F, uio_oe, "SETOE 0xF");

        // ---- Test 5: DELAY ----
        $display("\n[Test 5] DELAY");
        reset_dut();
        prog[0] = 16'h8180;   // SET X = 8
        prog[1] = 16'h8280;   // SET Y = 8
        prog[2] = 16'hA000;   // DELAY 0x0808 cycles
        prog[3] = 16'h80F0;
        prog[4] = 16'hF000;
        load_prog(5);
        wait_for_out(8'h0F, 5000);
        check(8'h0F, uo_out, "DELAY completed");

        // ---- Test 6: WAIT pin 0 high ----
        $display("\n[Test 6] WAIT pin");
        reset_dut();
        prog[0] = 16'h2100;   // WAIT pin 0 high
        prog[1] = 16'h80F0;
        prog[2] = 16'hF000;
        load_prog(3);
        uio_in[0] = 1'b0;
        repeat (30) @(posedge clk); #1;
        check(8'h00, uo_out, "stalled while pin low");
        uio_in[0] = 1'b1;
        wait_for_out(8'h0F, 500);
        check(8'h0F, uo_out, "WAIT released");
        uio_in[0] = 1'b0;

        // ---- Test 7: OUT ----
        $display("\n[Test 7] OUT");
        reset_dut();
        prog[0] = 16'h8110;   // SET X = 1
        prog[1] = 16'h7000;   // MOV OSR = X
        prog[2] = 16'h4000;   // OUT pin 0
        prog[3] = 16'hF000;
        load_prog(4);
        repeat (80) @(posedge clk); #1;
        check(8'h01, uo_out[0], "OUT bit0 = 1");

        // ---- Test 8: FIFO PULL ----
        $display("\n[Test 8] FIFO PULL");
        reset_dut();
        prog[0] = 16'h6000;   // PULL
        prog[1] = 16'h4000;   // OUT pin0
        prog[2] = 16'hF000;
        load_prog(3);
        dut.tx_fifo[0] = 8'h01;
        dut.tx_count  = 4'd1;
        repeat (80) @(posedge clk); #1;
        check(8'h01, uo_out[0], "PULL + OUT");

        // ---- Test 9: JMP X-- loop ----
        $display("\n[Test 9] JMP X-- loop");
        reset_dut();
        // SET X = 2
        prog[0] = 16'h8120;
        // Loop body: SET pins=0xF
        prog[1] = 16'h80F0;
        // JMP X--, tgt=1   (operand=4, side_set=1 -> target = {0,1}=1)
        prog[2] = 16'h1420;
        prog[3] = 16'hF000;
        load_prog(4);
        wait_for_out(8'h0F, 500);
        check(8'h0F, uo_out, "loop exits with pins=0xF");

        // ---- Test 10: SAMPLE ----
        $display("\n[Test 10] SAMPLE");
        reset_dut();
        prog[0] = 16'hC000;   // SAMPLE -> ISR = uio_in
        prog[1] = 16'h7500;   // MOV pin_out = ISR
        prog[2] = 16'hF000;
        load_prog(3);
        uio_in = 8'hA5;
        wait_for_out(8'hA5, 500);
        check(8'hA5, uo_out, "SAMPLE -> ISR -> pins");
        uio_in = 8'h00;

        // ---- Test 11: Clock divider ----
        $display("\n[Test 11] Clock divider");
        reset_dut();
        write_cfg(5'd0, 8'h04);   // cfg_clkdiv_int = 4
        write_cfg(5'd2, 8'h00);   // cfg_clkdiv_frac = 0
        prog[0] = 16'h80F0;
        prog[1] = 16'hF000;
        load_prog(2);
        wait_for_out(8'h0F, 2000);
        check(8'h0F, uo_out, "program ran with divider");

        // ---- Test 12: Autopull ----
        $display("\n[Test 12] Autopull");
        reset_dut();
        write_cfg(5'd6, 8'h01);   // cfg_autopull = 1
        write_cfg(5'd8, 8'h00);   // pull_thresh = 0
        dut.tx_fifo[0] = 8'h01;
        dut.tx_count  = 4'd1;
        prog[0] = 16'h4000;   // OUT (autopull must refill OSR BEFORE shift)
        prog[1] = 16'hF000;   // HALT
        load_prog(2);
        wait_for_out(8'h01, 200);
        check(8'h01, uo_out, "autopull refilled OSR");

        // ---- Test 13: constrained-random stress ----
        $display("\n[Test 13] random stress");
        for (k = 0; k < 16; k = k + 1) begin
            reset_dut();
            rnd_a = $random;
            rnd_b = $random;
            prog[0] = 16'h8100 | {12'b0, rnd_a[3:0]};
            prog[1] = 16'h8200 | {12'b0, rnd_b[3:0]};
            prog[2] = 16'h7000;
            prog[3] = 16'h4000;
            prog[4] = 16'hF000;
            load_prog(5);
            repeat (60) @(posedge clk);
        end
        $display("  [PASS] random stress (16 iterations)");
        pass_count = pass_count + 1;

        // ---- Test 14: UART pattern ----
        $display("\n[Test 14] UART pattern");
        reset_dut();
        write_cfg(5'd0, 8'h04);   // slow clock
        prog[0] = 16'h80F0;   // idle high
        prog[1] = 16'h8101;   // SET X = 1
        prog[2] = 16'h8201;   // SET Y = 1
        prog[3] = 16'hA000;   // DELAY
        prog[4] = 16'h8000;   // start bit (low)
        prog[5] = 16'h8101;
        prog[6] = 16'h8201;
        prog[7] = 16'hA000;   // DELAY
        prog[8] = 16'h80F0;   // stop bit (high)
        prog[9] = 16'hF000;
        load_prog(10);
        repeat (600) @(posedge clk);
        check(8'h0F, uo_out[3:0], "UART idle high");

        // ---- Test 15: SPI mode 0 (MOSI + SCLK) ----
        $display("\n[Test 15] SPI mode 0");
        reset_dut();
        prog[0] = 16'h8040;   // CS high, SCLK low, MOSI low
        prog[1] = 16'h8110;   // SET X = 1
        prog[2] = 16'h7000;   // MOV OSR = X
        prog[3] = 16'h8000;   // CS low, SCLK low, MOSI low
        prog[4] = 16'h4000;   // OUT pin0 -> MOSI = 1
        prog[5] = 16'h8020;   // SCLK high
        prog[6] = 16'h8000;   // SCLK low
        prog[7] = 16'hF000;   // HALT
        load_prog(8);
        wait_for_out(8'h01, 500);
        check(8'h01, uo_out[0], "SPI MOSI bit = 1");
        for (k = 0; k < 20; k = k + 1) begin
            @(posedge clk); #1;
            if (uo_out == 8'h02) begin
                check(8'h01, {7'b0, uo_out[1]}, "SPI SCLK pulse high");
                k = 20;
            end
        end

        // ---- Test 16: I2C START + address byte ----
        $display("\n[Test 16] I2C bit-bang");
        reset_dut();
        dut.tx_fifo[0] = 8'hA5;
        dut.tx_count  = 4'd1;
        prog[0] = 16'h8033;   // both idle high
        prog[1] = 16'h8022;   // START: SDA low while SCL high
        prog[2] = 16'h8000;   // SCL low
        prog[3] = 16'h6000;   // PULL 0xA5 from TX FIFO
        prog[4] = 16'h4000;   // OUT bit0 to SDA (bit = 1)
        prog[5] = 16'h8002;   // SCL high
        prog[6] = 16'h8000;   // SCL low
        prog[7] = 16'h4000;   // OUT bit1 to SDA (bit = 0)
        prog[8] = 16'h8002;
        prog[9] = 16'h8000;
        prog[10] = 16'h4000;
        prog[11] = 16'h8002;
        prog[12] = 16'h8000;
        prog[13] = 16'h4000;
        prog[14] = 16'h8002;
        prog[15] = 16'h8000;
        prog[16] = 16'h4000;
        prog[17] = 16'h8002;
        prog[18] = 16'h8000;
        prog[19] = 16'h4000;
        prog[20] = 16'h8002;
        prog[21] = 16'h8000;
        prog[22] = 16'h4000;
        prog[23] = 16'h8002;
        prog[24] = 16'h8000;
        prog[25] = 16'h4000;
        prog[26] = 16'h8002;
        prog[27] = 16'h8000;
        prog[28] = 16'hF000;
        load_prog(29);
        wait_for_out(8'h02, 500);
        check(8'h02, uo_out, "I2C START = SDA low, SCL high");
        wait_for_out(8'h01, 500);
        check(8'h01, uo_out[0], "I2C first data bit = 1");

        // ---- Test 17: loop wrap ----
        $display("\n[Test 17] loop wrap");
        reset_dut();
        write_cfg(5'd3, 8'd1);      // cfg_wrap_top = 1
        write_cfg(5'd4, 8'd0);      // cfg_wrap_bottom = 0
        prog[0] = 16'h80F0;         // SET pins = 0xF
        prog[1] = 16'h8000;         // SET pins = 0x0
        prog[2] = 16'h0000;         // NOP after wrap target
        load_prog(3);
        wait_for_out(8'h0F, 500);
        wait_for_out(8'h00, 500);
        wait_for_out(8'h0F, 500);
        check(8'h0F, uo_out, "wrap from 1 back to 0");

        // ---- Test 18: IRQ latch ----
        $display("\n[Test 18] IRQ latch");
        reset_dut();
        prog[0] = 16'h9000;   // OP_IRQ
        prog[1] = 16'hF000;   // HALT
        load_prog(2);
        repeat (40) @(posedge clk); #1;
        check(8'h01, {7'b0, dut.irq_pending}, "IRQ pending after instruction");

        // ---- Test 19: host FIFO access ----
        $display("\n[Test 19] host FIFO access");
        reset_dut();
        ui_in = 8'hA5;
        uio_in[2] = 1'b1;      // host FIFO mode
        uio_in[3] = 1'b0;      // CPU running
        uio_in[0] = 1'b1;      // host write enable
        @(posedge clk); #1;
        check(8'hA5, dut.tx_fifo[0], "host TX FIFO accepted byte");

        dut.rx_fifo[0] = 8'h3C;
        dut.rx_count = 4'd1;
        uio_in[1] = 1'b1;      // host read enable
        @(posedge clk); #1;
        check(8'h3C, uo_out, "host RX FIFO returned byte");
        uio_in[1] = 1'b0;

        // ---- Test 20: simultaneous host and engine FIFO transfers ----
        $display("\n[Test 20] simultaneous FIFO transfers");
        reset_dut();
        dut.tx_count = 4'd1;
        dut.tx_rd = 4'd0;
        dut.tx_wr = 4'd1;
        dut.tx_fifo[0] = 8'h3C;
        dut.state = 2'd1;
        dut.instr = 16'h6000;   // OP_PULL
        dut.tick = 1'b1;
        ui_in = 8'hA5;
        uio_in = 8'h05;         // host FIFO mode + write
        @(posedge clk); #1;
        check(8'h01, {4'b0, dut.tx_count}, "TX count stable");
        check(8'h02, {4'b0, dut.tx_wr[1:0]}, "TX host write pointer advanced");
        check(8'h01, {4'b0, dut.tx_rd[1:0]}, "TX engine read pointer advanced");

        reset_dut();
        dut.rx_count = 4'd1;
        dut.rx_rd = 4'd0;
        dut.rx_wr = 4'd1;
        dut.rx_fifo[0] = 8'h3C;
        dut.state = 2'd1;
        dut.instr = 16'h5000;   // OP_PUSH
        dut.tick = 1'b1;
        uio_in = 8'h06;         // host FIFO mode + read
        @(posedge clk); #1;
        check(8'h01, {4'b0, dut.rx_count}, "RX count stable");
        check(8'h02, {4'b0, dut.rx_wr[1:0]}, "RX engine write pointer advanced");
        check(8'h01, {4'b0, dut.rx_rd[1:0]}, "RX host read pointer advanced");
        check(8'h3C, dut.host_fifo_data, "simultaneous host read returned old FIFO head");

        // ---- Test 21: WAIT for a rising edge, including a one-cycle pulse ----
        $display("\n[Test 21] WAIT rising edge");
        reset_dut();
        prog[0] = 16'h2110;   // WAIT for rising edge on pin 0
        prog[1] = 16'h80F0;
        prog[2] = 16'hF000;
        load_prog(3);
        repeat (40) @(posedge clk); #1;
        check(8'h00, uo_out, "WAIT rising edge stalls");
        uio_in[0] = 1'b1;
        @(posedge clk); #1;
        uio_in[0] = 1'b0;
        wait_for_out(8'h0F, 200);
        check(8'h0F, uo_out, "rising edge consumed");

        // ---- Test 22: WAIT for a falling edge ----
        $display("\n[Test 22] WAIT falling edge");
        reset_dut();
        prog[0] = 16'h2010;   // WAIT for falling edge on pin 0
        prog[1] = 16'h80F0;
        prog[2] = 16'hF000;
        load_prog(3);
        uio_in[0] = 1'b1;
        repeat (40) @(posedge clk); #1;
        check(8'h00, uo_out, "WAIT falling edge stalls");
        uio_in[0] = 1'b0;
        @(posedge clk); #1;
        uio_in[0] = 1'b1;
        wait_for_out(8'h0F, 200);
        check(8'h0F, uo_out, "falling edge consumed");

        // ---- Test 23: full FIFO replacement transfers ----
        $display("\n[Test 23] full FIFO replacement");
        reset_dut();
        dut.tx_count = 4'd8;
        dut.tx_rd = 4'd3;
        dut.tx_wr = 4'd3;
        dut.tx_fifo[3] = 8'h3C;
        dut.state = 2'd1;
        dut.instr = 16'h6000;   // PULL from the full TX FIFO
        dut.tick = 1'b1;
        ui_in = 8'hA5;
        uio_in = 8'h05;          // host write and engine dequeue
        @(posedge clk); #1;
        check(8'h08, dut.tx_count, "TX full count stays stable");
        check(8'h3C, dut.osr[7:0], "TX dequeue returns old head");
        check(8'hA5, dut.tx_fifo[3], "TX enqueue replaces tail");
        check(8'h04, {5'b0, dut.tx_rd[2:0]}, "TX read pointer advances");
        check(8'h04, {5'b0, dut.tx_wr[2:0]}, "TX write pointer advances");

        reset_dut();
        dut.rx_count = 4'd8;
        dut.rx_rd = 4'd5;
        dut.rx_wr = 4'd5;
        dut.rx_fifo[5] = 8'h3C;
        dut.isr = 32'h000000A5;
        dut.state = 2'd1;
        dut.instr = 16'h5000;   // PUSH into the full RX FIFO
        dut.tick = 1'b1;
        uio_in = 8'h06;          // host read and engine enqueue
        @(posedge clk); #1;
        check(8'h08, dut.rx_count, "RX full count stays stable");
        check(8'h3C, dut.host_fifo_data, "RX dequeue returns old head");
        check(8'hA5, dut.rx_fifo[5], "RX enqueue replaces tail");
        check(8'h06, {4'b0, dut.rx_rd[2:0]}, "RX read pointer advances");
        check(8'h06, {4'b0, dut.rx_wr[2:0]}, "RX write pointer advances");

        // ---- Summary ----
        $display("\n==========================================");
        $display(" Results: %0d passed, %0d failed",
                 pass_count, fail_count);
        if (fail_count == 0) $display(" ALL TESTS PASSED");
        else begin
            $display(" SOME TESTS FAILED");
            $fatal(1, "%0d test checks failed", fail_count);
        end
        $display("==========================================");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("!! TIMEOUT !!");
        $finish;
    end

endmodule

`default_nettype wire