/*
 * Copyright (c) 2026 Your Name
 * SPDX-License-Identifier: Apache-2.0
 *
 * Protocol Engine State Machine (PESM)
 * Tiny Tapeout CMOS5L - Jane Street Protocol Emulator ASIC Competition
 */

`default_nettype none

module tt_um_protocol_engine (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    reg [15:0] imem [0:31];

    reg [15:0] cfg_clkdiv_int;
    reg [7:0]  cfg_clkdiv_frac;
    reg [4:0]  cfg_wrap_top;
    reg [4:0]  cfg_wrap_bottom;
    reg [1:0]  cfg_shift_dir;
    reg        cfg_autopull;
    reg        cfg_autopush;
    reg [4:0]  cfg_pull_thresh;
    reg [4:0]  cfg_push_thresh;
    reg [3:0]  cfg_side_count;

    reg [15:0] clkdiv_int_cnt;
    reg [7:0]  clkdiv_frac_acc;
    reg        tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clkdiv_int_cnt  <= 16'd0;
            clkdiv_frac_acc <= 8'd0;
            tick            <= 1'b0;
        end else begin
            if (clkdiv_int_cnt == 16'd0) begin
                if (clkdiv_frac_acc >= 8'd255) begin
                    clkdiv_frac_acc <= 8'd0;
                    clkdiv_int_cnt  <= cfg_clkdiv_int;
                    tick            <= 1'b1;
                end else begin
                    clkdiv_frac_acc <= clkdiv_frac_acc + cfg_clkdiv_frac;
                    clkdiv_int_cnt  <= cfg_clkdiv_int;
                    tick            <= 1'b1;
                end
            end else begin
                clkdiv_int_cnt <= clkdiv_int_cnt - 1'b1;
                tick           <= 1'b0;
            end
        end
    end

    reg [4:0]  pc;
    reg [15:0] instr;
    reg [31:0] osr;
    reg [31:0] isr;
    reg [4:0]  osr_count;
    reg [4:0]  isr_count;
    reg [7:0]  x_reg;
    reg [7:0]  y_reg;
    reg [7:0]  pin_out;
    reg [7:0]  pin_oe;
    reg [15:0] delay_cnt;
    reg [1:0]  state;
    reg [1:0]  next_state;

    reg [3:0] side_mask;
    always @(*) begin
        case (cfg_side_count)
            4'd0: side_mask = 4'b0000;
            4'd1: side_mask = 4'b0001;
            4'd2: side_mask = 4'b0011;
            4'd3: side_mask = 4'b0111;
            default: side_mask = 4'b1111;
        endcase
    end

    localparam S_FETCH = 2'd0;
    localparam S_EXEC  = 2'd1;
    localparam S_DELAY = 2'd2;

    reg [7:0] tx_fifo [0:7];
    reg [7:0] rx_fifo [0:7];
    reg [3:0] tx_wr, tx_rd, tx_count;
    reg [3:0] rx_wr, rx_rd, rx_count;
    wire tx_empty = (tx_count == 4'd0);
    wire rx_full  = (rx_count == 4'd8);

    // Autopull: only when the current instruction is OUT (consuming OSR)
    // Autopush: only when the current instruction is IN (filling ISR)
    // These gates prevent autopull/autopush from firing during idle/HALT cycles.
    wire autopull_hit = cfg_autopull && (osr_count <= cfg_pull_thresh) && !tx_empty
                        && (instr[15:12] == 4'h4);   // OP_OUT
    wire autopush_hit = cfg_autopush && (isr_count >= cfg_push_thresh) && !rx_full
                        && (instr[15:12] == 4'h3);   // OP_IN

    // Effective OSR value: if autopull fires this cycle, OUT sees the refilled data
    wire [31:0] osr_eff       = autopull_hit ? {24'b0, tx_fifo[tx_rd[2:0]]} : osr;
    wire [4:0]  osr_count_eff = autopull_hit ? 5'd8 : osr_count;

    reg [15:0] load_shift;
    reg [7:0]  cfg_shift;
    reg [3:0]  load_bit;
    reg [2:0]  cfg_bit;
    reg [4:0]  load_addr;
    reg        host_clk_d;
    reg        load_mode;
    reg        uio3_d;
    wire       host_clk_rise = uio_in[1] & ~host_clk_d;
    wire       load_start    = uio_in[3] & ~uio3_d;
    wire [7:0] cfg_byte      = {cfg_shift[6:0], uio_in[0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            host_clk_d <= 1'b0;
            uio3_d     <= 1'b0;
        end else begin
            host_clk_d <= uio_in[1];
            uio3_d     <= uio_in[3];
        end
    end

    wire [3:0] opcode    = instr[15:12];
    wire [3:0] operand   = instr[11:8];
    wire [3:0] side_set  = instr[7:4];
    wire [3:0] delay_imm = instr[3:0];
    wire [4:0] jump_tgt  = {operand[3], side_set};

    localparam OP_NOP    = 4'h0;
    localparam OP_JMP    = 4'h1;
    localparam OP_WAIT   = 4'h2;
    localparam OP_IN     = 4'h3;
    localparam OP_OUT    = 4'h4;
    localparam OP_PUSH   = 4'h5;
    localparam OP_PULL   = 4'h6;
    localparam OP_MOV    = 4'h7;
    localparam OP_SET    = 4'h8;
    localparam OP_IRQ    = 4'h9;
    localparam OP_DELAY  = 4'hA;
    localparam OP_TOGGLE = 4'hB;
    localparam OP_SAMPLE = 4'hC;
    localparam OP_HALT   = 4'hF;

    reg [7:0] next_pin_out;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 5'd0; instr <= 16'h0000;
            osr <= 32'h0; isr <= 32'h0;
            osr_count <= 5'd0; isr_count <= 5'd0;
            x_reg <= 8'h0; y_reg <= 8'h0;
            pin_out <= 8'h0; pin_oe <= 8'h0;
            delay_cnt <= 16'h0; state <= S_FETCH; next_state <= S_FETCH;
            tx_wr <= 4'd0; tx_rd <= 4'd0; tx_count <= 4'd0;
            rx_wr <= 4'd0; rx_rd <= 4'd0; rx_count <= 4'd0;
            load_shift <= 16'h0; cfg_shift <= 8'h0;
            load_bit <= 4'd0; cfg_bit <= 3'd0;
            load_addr <= 5'd0; load_mode <= 1'b0;
            cfg_clkdiv_int <= 16'd0; cfg_clkdiv_frac <= 8'd0;
            cfg_wrap_top <= 5'd31; cfg_wrap_bottom <= 5'd0;
            cfg_shift_dir <= 2'd0;
            cfg_autopull <= 1'b0; cfg_autopush <= 1'b0;
            cfg_pull_thresh <= 5'd0; cfg_push_thresh <= 5'd31;
            cfg_side_count <= 4'd0;
            for (i = 0; i < 32; i = i + 1) imem[i] <= 16'hF000;
        end else begin

            if (load_start) begin
                load_mode  <= 1'b1;
                load_addr  <= 5'd0;
                load_bit   <= 4'd0;
                cfg_bit    <= 3'd0;
                load_shift <= 16'h0;
                cfg_shift  <= 8'h0;
            end else if (uio_in[3]) begin
                load_mode <= 1'b1;
                if (host_clk_rise) begin
                    if (uio_in[2] == 1'b0) begin
                        load_shift <= {load_shift[14:0], uio_in[0]};
                        if (load_bit == 4'd15) begin
                            imem[load_addr] <= {load_shift[14:0], uio_in[0]};
                            load_bit  <= 4'd0;
                            load_addr <= load_addr + 1'b1;
                        end else begin
                            load_bit <= load_bit + 1'b1;
                        end
                    end else begin
                        cfg_shift <= cfg_byte[6:0];
                        if (cfg_bit == 3'd7) begin
                            case (load_addr)
                                5'd0:  cfg_clkdiv_int[7:0]  <= cfg_byte;
                                5'd1:  cfg_clkdiv_int[15:8] <= cfg_byte;
                                5'd2:  cfg_clkdiv_frac      <= cfg_byte;
                                5'd3:  cfg_wrap_top         <= cfg_byte[4:0];
                                5'd4:  cfg_wrap_bottom      <= cfg_byte[4:0];
                                5'd5:  cfg_shift_dir        <= cfg_byte[1:0];
                                5'd6:  cfg_autopull         <= cfg_byte[0];
                                5'd7:  cfg_autopush         <= cfg_byte[0];
                                5'd8:  cfg_pull_thresh      <= cfg_byte[4:0];
                                5'd9:  cfg_push_thresh      <= cfg_byte[4:0];
                                5'd10: cfg_side_count       <= cfg_byte[3:0];
                                default: ;
                            endcase
                            cfg_bit   <= 3'd0;
                            load_addr <= load_addr + 1'b1;
                        end else begin
                            cfg_bit <= cfg_bit + 1'b1;
                        end
                    end
                end
            end else if (load_mode) begin
                load_mode  <= 1'b0;
                pc         <= 5'd0;
                state      <= S_FETCH;
                next_state <= S_FETCH;
                osr_count  <= 5'd0;
                isr_count  <= 5'd0;
            end

            if (!uio_in[3] && !load_mode && tick) begin
                case (state)
                    S_FETCH: begin
                        instr <= imem[pc];
                        state <= S_EXEC;
                    end

                    S_EXEC: begin
                        next_pin_out = pin_out;

                        if (side_mask != 4'b0000 &&
                            opcode != OP_SET && opcode != OP_TOGGLE) begin
                            next_pin_out[3:0] =
                                (next_pin_out[3:0] & ~side_mask) |
                                (side_set & side_mask);
                        end

                        next_state = S_FETCH;

                        case (opcode)
                            OP_NOP: pc <= pc + 1'b1;

                            OP_JMP: begin
                                case (operand[2:0])
                                    3'b100: begin
                                        if (x_reg != 8'h0) begin
                                            x_reg <= x_reg - 1'b1;
                                            pc <= jump_tgt;
                                        end else pc <= pc + 1'b1;
                                    end
                                    3'b101: begin
                                        if (y_reg != 8'h0) begin
                                            y_reg <= y_reg - 1'b1;
                                            pc <= jump_tgt;
                                        end else pc <= pc + 1'b1;
                                    end
                                    3'b110: begin
                                        if (x_reg == 8'h0) pc <= jump_tgt;
                                        else pc <= pc + 1'b1;
                                    end
                                    3'b111: begin
                                        if (y_reg == 8'h0) pc <= jump_tgt;
                                        else pc <= pc + 1'b1;
                                    end
                                    default: pc <= jump_tgt;
                                endcase
                            end

                            OP_WAIT: begin
                                if ((operand[1:0] == 2'b00 && uio_in[operand[3:1]] == 1'b0) ||
                                    (operand[1:0] == 2'b01 && uio_in[operand[3:1]] == 1'b1))
                                    pc <= pc + 1'b1;
                                else
                                    next_state = S_EXEC;
                            end

                            OP_IN: begin
                                isr <= {isr[30:0], uio_in[operand[2:0]]};
                                isr_count <= isr_count + 1'b1;
                                pc <= pc + 1'b1;
                            end

                            OP_OUT: begin
                                next_pin_out[operand[2:0]] = osr_eff[0];
                                if (cfg_shift_dir == 2'd0) osr <= {1'b0, osr_eff[31:1]};
                                else                       osr <= {osr_eff[30:0], 1'b0};
                                if (osr_count_eff > 5'd0)
                                    osr_count <= osr_count_eff - 1'b1;
                                if (autopull_hit) begin
                                    tx_rd    <= tx_rd + 1'b1;
                                    tx_count <= tx_count - 1'b1;
                                end
                                pc <= pc + 1'b1;
                            end

                            OP_PUSH: begin
                                if (!rx_full) begin
                                    rx_fifo[rx_wr[2:0]] <= isr[7:0];
                                    rx_wr <= rx_wr + 1'b1;
                                    rx_count <= rx_count + 1'b1;
                                    isr_count <= 5'd0;
                                    pc <= pc + 1'b1;
                                end else next_state = S_EXEC;
                            end

                            OP_PULL: begin
                                if (!tx_empty) begin
                                    osr <= {24'b0, tx_fifo[tx_rd[2:0]]};
                                    tx_rd <= tx_rd + 1'b1;
                                    tx_count <= tx_count - 1'b1;
                                    osr_count <= 5'd8;
                                    pc <= pc + 1'b1;
                                end else next_state = S_EXEC;
                            end

                            OP_MOV: begin
                                case (operand[2:0])
                                    3'h0: osr <= {24'b0, x_reg};
                                    3'h1: x_reg <= osr[7:0];
                                    3'h2: osr <= {24'b0, y_reg};
                                    3'h3: y_reg <= osr[7:0];
                                    3'h4: isr <= {24'b0, uio_in};
                                    3'h5: next_pin_out = isr[7:0];
                                    3'h6: next_pin_out = x_reg;
                                    3'h7: next_pin_out = y_reg;
                                    default: ;
                                endcase
                                pc <= pc + 1'b1;
                            end

                            OP_SET: begin
                                case (operand[2:0])
                                    3'h0: next_pin_out[3:0] = side_set;
                                    3'h1: x_reg <= {4'b0, side_set};
                                    3'h2: y_reg <= {4'b0, side_set};
                                    3'h3: pin_oe <= {4'b0, side_set};
                                    3'h4: next_pin_out[7:4] = side_set;
                                    default: ;
                                endcase
                                pc <= pc + 1'b1;
                            end

                            OP_IRQ: pc <= pc + 1'b1;

                            OP_DELAY: begin
                                if ({x_reg, y_reg} == 16'h0) begin
                                    pc <= pc + 1'b1;
                                end else begin
                                    delay_cnt  <= {x_reg, y_reg};
                                    pc         <= pc + 1'b1;
                                    next_state = S_DELAY;
                                end
                            end

                            OP_TOGGLE: begin
                                next_pin_out[3:0] = next_pin_out[3:0] ^ side_set;
                                pc <= pc + 1'b1;
                            end

                            OP_SAMPLE: begin
                                isr <= {24'b0, uio_in};
                                isr_count <= 5'd8;
                                pc <= pc + 1'b1;
                            end

                            OP_HALT: next_state = S_EXEC;

                            default: pc <= pc + 1'b1;
                        endcase

                        pin_out <= next_pin_out;

                        // Autopush (autopull is now folded into OP_OUT)
                        if (autopush_hit) begin
                            rx_fifo[rx_wr[2:0]] <= {isr[6:0], uio_in[operand[2:0]]};
                            rx_wr <= rx_wr + 1'b1;
                            rx_count <= rx_count + 1'b1;
                            isr_count <= 5'd0;
                        end

                        if (delay_imm != 4'd0 && next_state == S_FETCH) begin
                            delay_cnt  <= {12'b0, delay_imm};
                            next_state = S_DELAY;
                        end

                        if (next_state != S_EXEC)
                            state <= next_state;
                    end

                    S_DELAY: begin
                        if (delay_cnt == 16'd0) state <= S_FETCH;
                        else                    delay_cnt <= delay_cnt - 1'b1;
                    end

                    default: state <= S_FETCH;
                endcase
            end
        end
    end

    assign uo_out  = pin_out;
    assign uio_out = pin_out;
    assign uio_oe  = pin_oe;

    wire _unused = &{ena, ui_in, 1'b0};

endmodule

`default_nettype wire