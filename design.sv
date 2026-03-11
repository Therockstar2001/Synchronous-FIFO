module sync_fifo #(
  parameter int DATA_W = 8,
  parameter int DEPTH  = 16
)(
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         wr_en,
  input  logic                         rd_en,
  input  logic [DATA_W-1:0]            wdata,

  output logic [DATA_W-1:0]            rdata,
  output logic                         full,
  output logic                         empty,
  output logic [$clog2(DEPTH+1)-1:0]   count,

  output logic                         overflow,
  output logic                         underflow
);

  localparam int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

  logic [DATA_W-1:0] mem [0:DEPTH-1];
  logic [ADDR_W-1:0] wptr, rptr;

  wire do_write = wr_en && !full;
  wire do_read  = rd_en && !empty;

  always_comb begin
    empty = (count == 0);
    full  = (count == DEPTH);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr      <= '0;
      rptr      <= '0;
      count     <= '0;
      rdata     <= '0;
      overflow  <= 1'b0;
      underflow <= 1'b0;
    end else begin
      if (wr_en && full)
        overflow <= 1'b1;

      if (rd_en && empty)
        underflow <= 1'b1;

      if (do_write) begin
        mem[wptr] <= wdata;
        wptr      <= wptr + 1'b1;
      end

      if (do_read) begin
        rdata <= mem[rptr];
        rptr  <= rptr + 1'b1;
      end

      unique case ({do_write, do_read})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end

endmodule