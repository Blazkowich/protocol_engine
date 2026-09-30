// Formal properties for the WAIT engine
module wait_formal (
    input logic clk,
    input logic rst_n,
    input logic pin_level,
    input logic [1:0] wait_level
);

    logic waiting;
    logic released;

    // WAIT releases only when pin_level matches wait_level
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            waiting  <= 1'b0;
            released <= 1'b0;
        end else begin
            if (wait_level == 2'b00) begin
                // wait for low
                if (!pin_level) begin
                    released <= 1'b1;
                    waiting  <= 1'b0;
                end else begin
                    waiting  <= 1'b1;
                    released <= 1'b0;
                end
            end else if (wait_level == 2'b01) begin
                // wait for high
                if (pin_level) begin
                    released <= 1'b1;
                    waiting  <= 1'b0;
                end else begin
                    waiting  <= 1'b1;
                    released <= 1'b0;
                end
            end
        end
    end

    // Property: released implies pin matches expected level
    property p_release_correct;
        @(posedge clk) disable iff (!rst_n)
        released |-> (wait_level == 2'b00 ? !pin_level : pin_level);
    endproperty
    a_release_correct: assert property (p_release_correct);

    // Property: waiting implies pin does NOT match
    property p_wait_correct;
        @(posedge clk) disable iff (!rst_n)
        waiting |-> (wait_level == 2'b00 ? pin_level : !pin_level);
    endproperty
    a_wait_correct: assert property (p_wait_correct);

endmodule