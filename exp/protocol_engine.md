
# Entity: protocol_engine 
- **File**: protocol_engine.v

## Diagram
![Diagram](protocol_engine.svg "Diagram")
## Ports

| Port name | Direction | Type       | Description |
| --------- | --------- | ---------- | ----------- |
| ui_in     | input     | wire [7:0] |             |
| uo_out    | output    | wire [7:0] |             |
| uio_in    | input     | wire [7:0] |             |
| uio_out   | output    | wire [7:0] |             |
| uio_oe    | output    | wire [7:0] |             |
| ena       | input     | wire       |             |
| clk       | input     | wire       |             |
| rst_n     | input     | wire       |             |

## Signals

| Name                                                              | Type        | Description |
| ----------------------------------------------------------------- | ----------- | ----------- |
| imem [0:31]                                                       | reg [15:0]  |             |
| cfg_clkdiv_int                                                    | reg [15:0]  |             |
| cfg_clkdiv_frac                                                   | reg [7:0]   |             |
| cfg_wrap_top                                                      | reg [4:0]   |             |
| cfg_wrap_bottom                                                   | reg [4:0]   |             |
| cfg_shift_dir                                                     | reg [1:0]   |             |
| cfg_autopull                                                      | reg         |             |
| cfg_autopush                                                      | reg         |             |
| cfg_pull_thresh                                                   | reg [4:0]   |             |
| cfg_push_thresh                                                   | reg [4:0]   |             |
| cfg_side_count                                                    | reg [3:0]   |             |
| cfg_side_oe                                                       | reg         |             |
| clkdiv_int_cnt                                                    | reg [15:0]  |             |
| clkdiv_frac_acc                                                   | reg [7:0]   |             |
| tick                                                              | reg         |             |
| clkdiv_frac_sum = {1'b0, clkdiv_frac_acc}                         | wire [8:0]  |             |
| pc                                                                | reg [4:0]   |             |
| instr                                                             | reg [15:0]  |             |
| osr                                                               | reg [31:0]  |             |
| isr                                                               | reg [31:0]  |             |
| osr_count                                                         | reg [4:0]   |             |
| isr_count                                                         | reg [4:0]   |             |
| x_reg                                                             | reg [7:0]   |             |
| y_reg                                                             | reg [7:0]   |             |
| pin_out                                                           | reg [7:0]   |             |
| pin_oe                                                            | reg [7:0]   |             |
| delay_cnt                                                         | reg [15:0]  |             |
| state                                                             | reg [1:0]   |             |
| next_state                                                        | reg [1:0]   |             |
| irq_pending                                                       | reg         |             |
| host_fifo_data                                                    | reg [7:0]   |             |
| pin_in_prev                                                       | reg [7:0]   |             |
| wait_rise_pending                                                 | reg [7:0]   |             |
| wait_fall_pending                                                 | reg [7:0]   |             |
| side_mask                                                         | reg [3:0]   |             |
| tx_fifo [0:7]                                                     | reg [7:0]   |             |
| rx_fifo [0:7]                                                     | reg [7:0]   |             |
| tx_wr                                                             | reg [3:0]   |             |
| tx_rd                                                             | reg [3:0]   |             |
| tx_count                                                          | reg [3:0]   |             |
| rx_wr                                                             | reg [3:0]   |             |
| rx_rd                                                             | reg [3:0]   |             |
| rx_count                                                          | reg [3:0]   |             |
| tx_empty = (tx_count == 4'd0)                                     | wire        |             |
| rx_full  = (rx_count == 4'd8)                                     | wire        |             |
| host_fifo_mode = (~uio_in[3]) & uio_in[2]                         | wire        |             |
| host_write_req = host_fifo_mode & uio_in[0]                       | wire        |             |
| host_read_req  = host_fifo_mode & uio_in[1]                       | wire        |             |
| rx_dequeue = host_read_req && (rx_count != 4'd0)                  | wire        |             |
| protocol_in = {ui_in[3:0], uio_in[7:4]}                           | wire [7:0]  |             |
| autopull_hit = cfg_autopull && (osr_coun                          | wire        |             |
| autopush_hit = cfg_autopush && (isr_coun                          | wire        |             |
| tx_fifo_word                                                      | wire [31:0] |             |
| osr_eff       = autopull_hit ? tx_fifo_word : osr                 | wire [31:0] |             |
| out_bit       = cfg_shift_dir == 2'd0 ? osr_eff[0] : osr_eff[31]  | wire        |             |
| osr_count_eff = autopull_hit ? 5'd8 : osr_count                   | wire [4:0]  |             |
| load_shift                                                        | reg [15:0]  |             |
| cfg_shift                                                         | reg [7:0]   |             |
| load_bit                                                          | reg [3:0]   |             |
| cfg_bit                                                           | reg [2:0]   |             |
| load_addr                                                         | reg [4:0]   |             |
| host_clk_d                                                        | reg         |             |
| load_mode                                                         | reg         |             |
| uio3_d                                                            | reg         |             |
| host_clk_rise = uio_in[1] & ~host_clk_d                           | wire        |             |
| load_start    = uio_in[3] & ~uio3_d                               | wire        |             |
| cfg_byte      = {cfg_shift[6:0], uio_in[0]}                       | wire [7:0]  |             |
| opcode    = instr[15:12]                                          | wire [3:0]  |             |
| operand   = instr[11:8]                                           | wire [3:0]  |             |
| side_set  = instr[7:4]                                            | wire [3:0]  |             |
| delay_imm = instr[3:0]                                            | wire [3:0]  |             |
| jump_tgt  = {operand[3], side_set}                                | wire [4:0]  |             |
| wait_rise_event = protocol_in & ~pin_in_prev                      | wire [7:0]  |             |
| wait_fall_event = ~protocol_in & pin_in_prev                      | wire [7:0]  |             |
| wait_edge_cycle = !uio_in[3] && !load_mode && tick &&             | wire        |             |
| wait_rise_clear_mask =                                            | wire [7:0]  |             |
| wait_fall_clear_mask =                                            | wire [7:0]  |             |
| tx_dequeue = tick && (state == S_EXEC) &&                         | wire        |             |
| tx_enqueue = host_write_req && ((tx_count != 4'd8) || tx_dequeue) | wire        |             |
| rx_enqueue = tick && (state                                       | wire        |             |
| pc_target                                                         | reg [4:0]   |             |
| next_pin_out                                                      | reg [7:0]   |             |
| i                                                                 | integer     |             |
| _unused = &{ena, 1'b0}                                            | wire        |             |

## Constants

| Name      | Type | Value | Description |
| --------- | ---- | ----- | ----------- |
| S_FETCH   |      | 2'd0  |             |
| S_EXEC    |      | 2'd1  |             |
| S_DELAY   |      | 2'd2  |             |
| OP_NOP    |      | 4'h0  |             |
| OP_JMP    |      | 4'h1  |             |
| OP_WAIT   |      | 4'h2  |             |
| OP_IN     |      | 4'h3  |             |
| OP_OUT    |      | 4'h4  |             |
| OP_PUSH   |      | 4'h5  |             |
| OP_PULL   |      | 4'h6  |             |
| OP_MOV    |      | 4'h7  |             |
| OP_SET    |      | 4'h8  |             |
| OP_IRQ    |      | 4'h9  |             |
| OP_DELAY  |      | 4'hA  |             |
| OP_TOGGLE |      | 4'hB  |             |
| OP_SAMPLE |      | 4'hC  |             |
| OP_HALT   |      | 4'hF  |             |

## Processes
- unnamed: ( @(posedge clk or negedge rst_n) )
  - **Type:** always
- unnamed: ( @(*) )
  - **Type:** always
- unnamed: ( @(posedge clk or negedge rst_n) )
  - **Type:** always
- unnamed: ( @(posedge clk or negedge rst_n) )
  - **Type:** always
- unnamed: ( @(posedge clk or negedge rst_n) )
  - **Type:** always
- unnamed: ( @(posedge clk or negedge rst_n) )
  - **Type:** always

## State machines

![Diagram_state_machine_0]( fsm_protocol_engine_00.svg "Diagram")