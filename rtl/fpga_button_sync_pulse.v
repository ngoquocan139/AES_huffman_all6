module fpga_button_sync_pulse #(
  parameter integer DEBOUNCE_CYCLES = 500000
) (
  input  wire clk_i,
  input  wire rst_i,
  input  wire btn_i,
  output wire level_o,
  output wire pulse_o
);
  function integer clog2;
    input integer value;
    integer v;
    begin
      v = value - 1;
      for (clog2 = 0; v > 0; clog2 = clog2 + 1)
        v = v >> 1;
    end
  endfunction

  localparam integer COUNTER_WIDTH = (DEBOUNCE_CYCLES <= 1) ? 1 : clog2(DEBOUNCE_CYCLES);
  localparam [COUNTER_WIDTH-1:0] DEBOUNCE_LAST_W = DEBOUNCE_CYCLES - 1;

  reg btn_meta_r;
  reg btn_sync_r;
  reg stable_r;
  reg stable_d_r;
  reg [COUNTER_WIDTH-1:0] debounce_count_r;

  assign level_o = stable_r;
  assign pulse_o = stable_r & ~stable_d_r;

  always @(posedge clk_i) begin
    if (rst_i) begin
      btn_meta_r       <= 1'b0;
      btn_sync_r       <= 1'b0;
      stable_r         <= 1'b0;
      stable_d_r       <= 1'b0;
      debounce_count_r <= {COUNTER_WIDTH{1'b0}};
    end else begin
      btn_meta_r <= btn_i;
      btn_sync_r <= btn_meta_r;
      stable_d_r <= stable_r;

      if (btn_sync_r == stable_r) begin
        debounce_count_r <= {COUNTER_WIDTH{1'b0}};
      end else if (debounce_count_r == DEBOUNCE_LAST_W) begin
        stable_r         <= btn_sync_r;
        debounce_count_r <= {COUNTER_WIDTH{1'b0}};
      end else begin
        debounce_count_r <= debounce_count_r + {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
      end
    end
  end
endmodule
