module fifo_assertions #(
  parameter int DEPTH = 16
)(
  fifo_if vif
);

  wire do_write = vif.cb_mon.wr_en && !vif.cb_mon.full;
  wire do_read  = vif.cb_mon.rd_en && !vif.cb_mon.empty;

  property p_no_read_when_empty;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      vif.cb_mon.empty |-> !do_read;
  endproperty
  a_no_read_when_empty: assert property (p_no_read_when_empty);

  property p_no_write_when_full;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      vif.cb_mon.full |-> !do_write;
  endproperty
  a_no_write_when_full: assert property (p_no_write_when_full);

  property p_empty_count_consistent;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.empty == (vif.cb_mon.count == 0));
  endproperty
  a_empty_count_consistent: assert property (p_empty_count_consistent);

  property p_full_count_consistent;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.full == (vif.cb_mon.count == DEPTH));
  endproperty
  a_full_count_consistent: assert property (p_full_count_consistent);

  property p_count_in_range;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.count <= DEPTH);
  endproperty
  a_count_in_range: assert property (p_count_in_range);

endmodule