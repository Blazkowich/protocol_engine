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

    protocol_engine dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #10 clk = ~clk;   // 50 MHz

    integer pass_count = 0, fail_count = 0;
    integer i, j, k;
    integer cycle_count, last_tick_cycle, interval_first, interval_second, tick_count;
    reg [7:0] tx_byte;
    reg [15:0] prog [0:31];
    reg [31:0] rnd_a, rnd_b;

    wire i2c_scl = uio_oe[5] ? uio_out[5] : 1'b1;
    wire i2c_sda = (uio_oe[6] && !uio_out[6]) ? 1'b0 : uio_in[6];
    // ---------- Tasks ----------
    task reset_dut;
        begin
            rst_n = 1'b0; uio_in = 8'h00; ui_in = 8'h00;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task shift_cfg_byte(input [7:0] value);
        integer b;
        begin
            for (b = 7; b >= 0; b = b - 1) begin
                uio_in[0] = value[b];
                @(posedge clk); #1;
                uio_in[1] = 1'b1;
                @(posedge clk); #1;
                uio_in[1] = 1'b0;
                @(posedge clk); #1;
            end
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

    task load_protocol_config;
        integer cfg_index;
        reg [7:0] cfg_value;
        begin
            @(posedge clk); #1;
            uio_in[3] = 1'b1;
            uio_in[2] = 1'b1;
            @(posedge clk); #1;
            for (cfg_index = 0; cfg_index < 12; cfg_index = cfg_index + 1) begin
                case (cfg_index)
                    0: cfg_value = 8'd0;
                    1: cfg_value = 8'd0;
                    2: cfg_value = 8'd0;
                    3: cfg_value = 8'd31;
                    4: cfg_value = 8'd0;
                    5: cfg_value = 8'd1;
                    6: cfg_value = 8'd0;
                    7: cfg_value = 8'd0;
                    8: cfg_value = 8'd0;
                    9: cfg_value = 8'd31;
                    10: cfg_value = 8'd2;
                    11: cfg_value = 8'd1;
                    default: cfg_value = 8'd0;
                endcase
                shift_cfg_byte(cfg_value);
            end
            uio_in[3] = 1'b0;
            uio_in[1] = 1'b0;
            uio_in[0] = 1'b0;
            @(posedge clk); #1;
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
                5'd11: dut.cfg_side_oe          = data[0];
                default: ;
            endcase
            @(posedge clk); #1;
        end
    endtask

    task host_write_byte(input [7:0] data);
        begin
            ui_in = data;
            uio_in[2] = 1'b1;
            uio_in[3] = 1'b0;
            uio_in[0] = 1'b1;
            @(posedge clk); #1;
            uio_in[0] = 1'b0;
            uio_in[2] = 1'b0;
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
        check(8'hF0, uio_out, "UIO4-7 output routing");

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
        prog[0] = 16'h83F0;
        prog[1] = 16'hF000;
        load_prog(2);
        repeat (40) @(posedge clk); #1;
        check(8'hF0, uio_oe, "SETOE routes enable to UIO4-7");

        // ---- Test 5: DELAY ----
        $display("\n[Test 5] DELAY");
        reset_dut();
        prog[0] = 16'h8180;
        prog[1] = 16'h8280;
        prog[2] = 16'hA000;
        prog[3] = 16'h80F0;
        prog[4] = 16'hF000;
        load_prog(5);
        wait_for_out(8'h0F, 5000);
        check(8'h0F, uo_out, "DELAY completed");

        // ---- Test 6: WAIT pin 0 high ----
        $display("\n[Test 6] WAIT pin");
        reset_dut();
        prog[0] = 16'h2100;
        prog[1] = 16'h80F0;
        prog[2] = 16'hF000;
        load_prog(3);
        uio_in[4] = 1'b0;
        repeat (30) @(posedge clk); #1;
        check(8'h00, uo_out, "stalled while pin low");
        uio_in[4] = 1'b1;
        wait_for_out(8'h0F, 500);
        check(8'h0F, uo_out, "WAIT released");
        uio_in[4] = 1'b0;

        // ---- Test 7: OUT ----
        $display("\n[Test 7] OUT");
        reset_dut();
        prog[0] = 16'h8110;
        prog[1] = 16'h7000;
        prog[2] = 16'h4000;
        prog[3] = 16'hF000;
        load_prog(4);
        repeat (80) @(posedge clk); #1;
        check(8'h01, uo_out[0], "OUT bit0 = 1");

        // ---- Test 8: FIFO PULL ----
        $display("\n[Test 8] FIFO PULL");
        reset_dut();
        prog[0] = 16'h6000;
        prog[1] = 16'h4000;
        prog[2] = 16'hF000;
        load_prog(3);
        dut.fifo_storage.tx_fifo[0] = 8'h01;
        dut.tx_count = 4'd1;
        repeat (80) @(posedge clk); #1;
        check(8'h01, uo_out[0], "PULL + OUT");

        // ---- Test 9: JMP X-- loop ----
        $display("\n[Test 9] JMP X-- loop");
        reset_dut();
        prog[0] = 16'h8120;
        prog[1] = 16'h80F0;
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
        uio_in = 8'h50;
        ui_in = 8'h0A;
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
        dut.fifo_storage.tx_fifo[0] = 8'h01;
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

        // ---- Test 14: UART 8N1 transmit ----
        $display("\n[Test 14] UART 8N1 transmit");
        reset_dut();
        tx_byte = 8'hA5;
        host_write_byte(tx_byte);
        write_cfg(5'd0, 8'd4);
        write_cfg(5'd2, 8'd0);
        prog[0] = 16'h80F0;
        prog[1] = 16'h6000;
        prog[2] = 16'h8000;
        for (i = 0; i < 8; i = i + 1) prog[3+i] = 16'h4000;
        prog[11] = 16'h80F0;
        prog[12] = 16'hF000;
        load_prog(13);
        @(negedge uo_out[0]);
        repeat (4) @(posedge clk); #1;
        check(8'h00, {7'b0, uo_out[0]}, "UART start bit");
        for (i = 0; i < 8; i = i + 1) begin
            repeat (8) @(posedge clk); #1;
            check(tx_byte[i], {7'b0, uo_out[0]}, "UART LSB-first data bit");
        end
        repeat (8) @(posedge clk); #1;
        check(8'h01, {7'b0, uo_out[0]}, "UART stop bit");

        // ---- Test 15: SPI mode 0 byte transmit ----
        $display("\n[Test 15] SPI mode 0 byte transmit");
        reset_dut();
        tx_byte = 8'h96;
        host_write_byte(tx_byte);
        write_cfg(5'd0, 8'd2);
        write_cfg(5'd5, 8'd1);
        prog[0] = 16'h8040;
        prog[1] = 16'h8000;
        prog[2] = 16'h6000;
        for (i = 0; i < 8; i = i + 1) begin
            prog[3+i*3] = 16'h4000;
            prog[4+i*3] = 16'hB020;
            prog[5+i*3] = 16'hB020;
        end
        prog[27] = 16'h8040;
        prog[28] = 16'hF000;
        load_prog(29);
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge uo_out[1]); #1;
            check(tx_byte[7-i], {7'b0, uo_out[0]}, "SPI MSB-first MOSI bit");
            if (i == 0) check(8'h00, {7'b0, uo_out[2]}, "SPI CS active");
        end
        repeat (40) @(posedge clk); #1;
        check(8'h01, {7'b0, uo_out[2]}, "SPI CS deasserted");

        // ---- Test 16: I2C open-drain byte transaction ----
        $display("\n[Test 16] I2C open-drain byte transaction");
        reset_dut();
        tx_byte = 8'h96;
        host_write_byte(tx_byte);
        load_protocol_config();
        check(8'd2, dut.cfg_side_count, "host config loads side-set width");
        check(8'd1, dut.cfg_side_oe, "host config selects output-enable side-set");
        check(8'd1, dut.cfg_shift_dir, "host config selects MSB-first shift");
        uio_in[6] = 1'b1;      // Target releases SDA during data.
        prog[0] = 16'h8000;    // Low output values for open-drain lines
        prog[1] = 16'h8300;    // Release both lines
        prog[2] = 16'h8340;    // START: pull SDA low while SCL is released
        prog[3] = 16'h8320;    // Pull SCL low, release SDA
        prog[4] = 16'h6020;    // PULL byte while SCL stays low
        for (i = 0; i < 8; i = i + 1) begin
            prog[5+i*2] = 16'h4A20; // Set SDA direction and pull SCL low
            prog[6+i*2] = 16'h0000; // Release SCL without consuming another bit
        end
        prog[21] = 16'h8320;   // Pull SCL low and release SDA for ACK
        prog[22] = 16'h3200;   // Sample ACK while side-set releases SCL
        prog[23] = 16'h8320;   // Pull SCL low
        prog[24] = 16'h8360;   // Pull SDA low before STOP
        prog[25] = 16'h0000;   // Release SCL
        prog[26] = 16'h8300;   // Release SDA for STOP
        prog[27] = 16'hF000;
        load_prog(28);
        while (!(i2c_sda == 1'b0 && i2c_scl == 1'b1)) @(posedge clk);
        @(negedge i2c_scl);
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge i2c_scl); #1;
            check(tx_byte[7-i], {7'b0, i2c_sda}, "I2C MSB-first data bit");
        end
        uio_in[6] = 1'b0;      // Target pulls SDA low for ACK.
        while (dut.isr_count != 5'd1) @(posedge clk);
        uio_in[6] = 1'b1;
        repeat (20) @(posedge clk); #1;
        check(8'h00, {7'b0, dut.isr[0]}, "I2C target ACK sampled low");
        check(1'b1, i2c_scl, "I2C STOP releases SCL");
        check(1'b1, i2c_sda, "I2C STOP releases SDA");

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
        check(8'hA5, dut.fifo_storage.tx_fifo[0], "host TX FIFO accepted byte");

        dut.fifo_storage.rx_fifo[0] = 8'h3C;
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
        dut.fifo_storage.tx_fifo[0] = 8'h3C;
        dut.state = 2'd1;
        dut.instr = 16'h6000;   // OP_PULL
        dut.clock_divider.tick = 1'b1;
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
        dut.fifo_storage.rx_fifo[0] = 8'h3C;
        dut.state = 2'd1;
        dut.instr = 16'h5000;   // OP_PUSH
        dut.clock_divider.tick = 1'b1;
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
        uio_in[4] = 1'b1;
        @(posedge clk); #1;
        uio_in[4] = 1'b0;
        wait_for_out(8'h0F, 200);
        check(8'h0F, uo_out, "rising edge consumed");

        // ---- Test 22: WAIT for a falling edge ----
        $display("\n[Test 22] WAIT falling edge");
        reset_dut();
        prog[0] = 16'h2010;   // WAIT for falling edge on pin 0
        prog[1] = 16'h80F0;
        prog[2] = 16'hF000;
        load_prog(3);
        uio_in[4] = 1'b1;
        repeat (40) @(posedge clk); #1;
        check(8'h00, uo_out, "WAIT falling edge stalls");
        uio_in[4] = 1'b0;
        @(posedge clk); #1;
        uio_in[4] = 1'b1;
        wait_for_out(8'h0F, 200);
        check(8'h0F, uo_out, "falling edge consumed");

        // ---- Test 23: full FIFO replacement transfers ----
        $display("\n[Test 23] full FIFO replacement");
        reset_dut();
        dut.tx_count = 4'd8;
        dut.tx_rd = 4'd3;
        dut.tx_wr = 4'd3;
        dut.fifo_storage.tx_fifo[3] = 8'h3C;
        dut.state = 2'd1;
        dut.instr = 16'h6000;   // PULL from the full TX FIFO
        dut.clock_divider.tick = 1'b1;
        ui_in = 8'hA5;
        uio_in = 8'h05;          // host write and engine dequeue
        @(posedge clk); #1;
        check(8'h08, dut.tx_count, "TX full count stays stable");
        check(8'h3C, dut.osr[7:0], "TX dequeue returns old head");
        check(8'hA5, dut.fifo_storage.tx_fifo[3], "TX enqueue replaces tail");
        check(8'h04, {5'b0, dut.tx_rd[2:0]}, "TX read pointer advances");
        check(8'h04, {5'b0, dut.tx_wr[2:0]}, "TX write pointer advances");

        reset_dut();
        dut.rx_count = 4'd8;
        dut.rx_rd = 4'd5;
        dut.rx_wr = 4'd5;
        dut.fifo_storage.rx_fifo[5] = 8'h3C;
        dut.isr = 32'h000000A5;
        dut.state = 2'd1;
        dut.instr = 16'h5000;   // PUSH into the full RX FIFO
        dut.clock_divider.tick = 1'b1;
        uio_in = 8'h06;          // host read and engine enqueue
        @(posedge clk); #1;
        check(8'h08, dut.rx_count, "RX full count stays stable");
        check(8'h3C, dut.host_fifo_data, "RX dequeue returns old head");
        check(8'hA5, dut.fifo_storage.rx_fifo[5], "RX enqueue replaces tail");
        check(8'h06, {4'b0, dut.rx_rd[2:0]}, "RX read pointer advances");
        check(8'h06, {4'b0, dut.rx_wr[2:0]}, "RX write pointer advances");

        // ---- Test 24: fractional clock-divider periods ----
        $display("\n[Test 24] Fractional clock divider");
        reset_dut();
        write_cfg(5'd0, 8'd3);
        write_cfg(5'd2, 8'd128);
        dut.clock_divider.clkdiv_int_cnt = 16'd0;
        dut.clock_divider.clkdiv_frac_acc = 8'd0;
        cycle_count = 0;
        last_tick_cycle = 0;
        interval_first = 0;
        interval_second = 0;
        tick_count = 0;
        while (tick_count < 3) begin
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
            if (dut.tick) begin
                if (tick_count == 1)
                    interval_first = cycle_count - last_tick_cycle;
                if (tick_count == 2)
                    interval_second = cycle_count - last_tick_cycle;
                last_tick_cycle = cycle_count;
                tick_count = tick_count + 1;
            end
        end
        check(8'd3, interval_first, "fractional divider short period");
        check(8'd4, interval_second, "fractional divider long period");

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