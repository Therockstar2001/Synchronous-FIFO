module fifo_assertions #(
  parameter int DEPTH = 16
)(
  fifo_if vif
);

  // -----------------------------------------
  // Helper expressions
  // -----------------------------------------
  wire do_write = vif.cb_mon.wr_en && !vif.cb_mon.full;
  wire do_read  = vif.cb_mon.rd_en && !vif.cb_mon.empty;

  // =========================================================
  // Basic protocol safety
  // =========================================================

  // No accepted read when empty
  property p_no_read_when_empty;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      vif.cb_mon.empty |-> !do_read;
  endproperty
  a_no_read_when_empty: assert property (p_no_read_when_empty);

  // No accepted write when full
  property p_no_write_when_full;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      vif.cb_mon.full |-> !do_write;
  endproperty
  a_no_write_when_full: assert property (p_no_write_when_full);

  // =========================================================
  // Flag/count consistency
  // =========================================================

  // empty flag must match count==0
  property p_empty_count_consistent;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.empty == (vif.cb_mon.count == 0));
  endproperty
  a_empty_count_consistent: assert property (p_empty_count_consistent);

  // full flag must match count==DEPTH
  property p_full_count_consistent;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.full == (vif.cb_mon.count == DEPTH));
  endproperty
  a_full_count_consistent: assert property (p_full_count_consistent);

  // count must remain in legal range
  property p_count_in_range;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.count <= DEPTH);
  endproperty
  a_count_in_range: assert property (p_count_in_range);

  // =========================================================
  // Count transition correctness
  // =========================================================

  // Accepted write only -> count increments by 1
  property p_count_inc_on_write_only;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (do_write && !do_read) |=> (vif.cb_mon.count == $past(vif.cb_mon.count) + 1);
  endproperty
  a_count_inc_on_write_only: assert property (p_count_inc_on_write_only);

  // Accepted read only -> count decrements by 1
  property p_count_dec_on_read_only;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (!do_write && do_read) |=> (vif.cb_mon.count == $past(vif.cb_mon.count) - 1);
  endproperty
  a_count_dec_on_read_only: assert property (p_count_dec_on_read_only);

  // Accepted simultaneous read/write -> count unchanged
  property p_count_same_on_simultaneous_rw;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (do_write && do_read) |=> (vif.cb_mon.count == $past(vif.cb_mon.count));
  endproperty
  a_count_same_on_simultaneous_rw: assert property (p_count_same_on_simultaneous_rw);

  // Neither accepted -> count unchanged
  property p_count_same_on_no_accept;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (!do_write && !do_read) |=> (vif.cb_mon.count == $past(vif.cb_mon.count));
  endproperty
  a_count_same_on_no_accept: assert property (p_count_same_on_no_accept);

  // =========================================================
  // Reset behavior
  // =========================================================

  // On reset deasserted low, next active cycle should reflect empty FIFO state
  property p_reset_clears_fifo;
    @(posedge vif.clk)
      (!vif.cb_mon.rst_n) |=> (vif.cb_mon.count == 0 && vif.cb_mon.empty && !vif.cb_mon.full);
  endproperty
  a_reset_clears_fifo: assert property (p_reset_clears_fifo);

  // =========================================================
  // Sticky error flag behavior
  // =========================================================

  // If write attempted while full, overflow flag should assert by next cycle
  property p_overflow_flag_on_illegal_write;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.wr_en && vif.cb_mon.full) |=> vif.cb_mon.overflow;
  endproperty
  a_overflow_flag_on_illegal_write: assert property (p_overflow_flag_on_illegal_write);

  // If read attempted while empty, underflow flag should assert by next cycle
  property p_underflow_flag_on_illegal_read;
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.rd_en && vif.cb_mon.empty) |=> vif.cb_mon.underflow;
  endproperty
  a_underflow_flag_on_illegal_read: assert property (p_underflow_flag_on_illegal_read);

  // =========================================================
  // Useful cover properties (optional but valuable)
  // =========================================================

  c_empty_to_nonempty: cover property (
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.count == 0) ##1 (vif.cb_mon.count > 0)
  );

  c_nonempty_to_empty: cover property (
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.count > 0) ##1 (vif.cb_mon.count == 0)
  );

  c_full_reached: cover property (
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (vif.cb_mon.count == DEPTH)
  );

  c_simultaneous_rw: cover property (
    @(posedge vif.clk) disable iff (!vif.cb_mon.rst_n)
      (do_write && do_read)
  );

endmodule