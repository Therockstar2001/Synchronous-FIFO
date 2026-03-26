`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

`include "fifo_if.sv"
`include "fifo_assertions.sv"
`include "fifo_pkg.sv"

import fifo_pkg::*;

module tb_top;

  localparam int DATA_W  = 8;
  localparam int DEPTH   = 16;
  localparam int COUNT_W = $clog2(DEPTH+1);

  logic clk = 0;
  always #5 clk = ~clk;

  fifo_if #(
    .DATA_W (DATA_W),
    .COUNT_W(COUNT_W)
  ) vif(clk);

  sync_fifo #(
    .DATA_W(DATA_W),
    .DEPTH (DEPTH)
  ) dut (
    .clk      (clk),
    .rst_n    (vif.rst_n),
    .wr_en    (vif.wr_en),
    .rd_en    (vif.rd_en),
    .wdata    (vif.wdata),
    .rdata    (vif.rdata),
    .full     (vif.full),
    .empty    (vif.empty),
    .count    (vif.count),
    .overflow (vif.overflow),
    .underflow(vif.underflow)
  );

  fifo_assertions #(
    .DEPTH(DEPTH)
  ) sva_i(vif);

  initial begin
    vif.rst_n = 0;
    vif.wr_en = 0;
    vif.rd_en = 0;
    vif.wdata = '0;
    repeat (5) @(posedge clk);
    vif.rst_n = 1;
  end

  initial begin
    uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);
    uvm_config_db#(int)::set(null, "*", "DEPTH", DEPTH);
    run_test();
  end

endmodule