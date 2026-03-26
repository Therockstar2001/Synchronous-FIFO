interface fifo_if #(
  parameter int DATA_W  = 8,
  parameter int COUNT_W = 5
)(
  input logic clk
);

  logic                     rst_n;
  logic                     wr_en;
  logic                     rd_en;
  logic [DATA_W-1:0]        wdata;

  logic [DATA_W-1:0]        rdata;
  logic                     full;
  logic                     empty;
  logic [COUNT_W-1:0]       count;
  logic                     overflow;
  logic                     underflow;

  clocking cb_drv @(posedge clk);
    output rst_n, wr_en, rd_en, wdata;
    input  rdata, full, empty, count, overflow, underflow;
  endclocking

  clocking cb_mon @(posedge clk);
    input rst_n, wr_en, rd_en, wdata;
    input rdata, full, empty, count, overflow, underflow;
  endclocking

endinterface