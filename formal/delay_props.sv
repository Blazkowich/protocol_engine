// Formal properties for the DELAY engine
module delay_formal (
    input logic clk,
    input logic rst_n,
    input logic [15:0] delay_value,
    input logic start
);

    logic [15:0] cnt;
    logic busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt  <= '0;
            busy <= 1'b0;
        end else if (start && delay_value != 0) begin
            cnt  <= delay_value;
            busy <= 1'b1;
        end else if (busy) begin
            if (cnt == 0) busy <= 1'b0;
            else          cnt  <= cnt - 1;
        end
    end

    // Property 1: busy remains high until cnt reaches 0
    property p_busy_until_zero;
        @(posedge clk) disable iff (!rst_n)
        (busy && cnt != 0) |=> busy;
    endproperty
    a_busy_until_zero: assert property (p_busy_until_zero);

    // Property 2: cnt decreases by exactly 1 each cycle while busy
    property p_cnt_decrement;
        @(posedge clk) disable iff (!rst_n)
        (busy && cnt != 0) |=> (cnt == $past(cnt) - 1);
    endproperty
    a_cnt_decrement: assert property (p_cnt_decrement);

    // Property 3: busy clears exactly when cnt reaches 0
    property p_busy_clears;
        @(posedge clk) disable iff (!rst_n)
        (busy && cnt == 0) |=> !busy;
    endproperty
    a_busy_clears: assert property (p_busy_clears);

endmodule