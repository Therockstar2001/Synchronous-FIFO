package fifo_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum bit [1:0] {
    ACT_IDLE  = 2'b00,
    ACT_READ  = 2'b01,
    ACT_WRITE = 2'b10,
    ACT_RW    = 2'b11
  } fifo_act_e;

  // =========================================================
  // Transaction
  // =========================================================
  class fifo_item extends uvm_sequence_item;
    rand fifo_act_e act;
    rand bit [7:0]  data;

    constraint c_act_dist {
      act dist {
        ACT_IDLE  := 10,
        ACT_READ  := 30,
        ACT_WRITE := 30,
        ACT_RW    := 30
      };
    }

    `uvm_object_utils_begin(fifo_item)
      `uvm_field_enum(fifo_act_e, act, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "fifo_item");
      super.new(name);
    endfunction
  endclass

  // =========================================================
  // Sequencer
  // =========================================================
  class fifo_sequencer extends uvm_sequencer #(fifo_item);
    `uvm_component_utils(fifo_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  // =========================================================
  // Driver
  // =========================================================
  class fifo_driver extends uvm_driver #(fifo_item);
    `uvm_component_utils(fifo_driver)

    virtual fifo_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface must be set for fifo_driver via config DB")
    endfunction

    task run_phase(uvm_phase phase);
      fifo_item it;

      vif.cb_drv.wr_en <= 1'b0;
      vif.cb_drv.rd_en <= 1'b0;
      vif.cb_drv.wdata <= '0;

      forever begin
        seq_item_port.get_next_item(it);

        vif.cb_drv.wr_en <= (it.act == ACT_WRITE || it.act == ACT_RW);
        vif.cb_drv.rd_en <= (it.act == ACT_READ  || it.act == ACT_RW);
        vif.cb_drv.wdata <= it.data;

        @(vif.cb_drv);

        vif.cb_drv.wr_en <= 1'b0;
        vif.cb_drv.rd_en <= 1'b0;

        seq_item_port.item_done();
      end
    endtask
  endclass

  // =========================================================
  // Monitor + Coverage
  // =========================================================
  class fifo_monitor extends uvm_component;
    `uvm_component_utils(fifo_monitor)

    virtual fifo_if vif;
    uvm_analysis_port #(fifo_item) ap;
    int DEPTH = 16;

    // sampled helper variables
    bit [1:0] op_code;
    bit       wr_fire;
    bit       rd_fire;
    bit       overflow_attempt;
    bit       underflow_attempt;
    int       occ_sample;
    int       prev_occ;
    bit       sim_rw;

    covergroup cg_fifo;
      option.per_instance = 1;

      // -----------------------------------------
      // Raw requested operation
      // -----------------------------------------
      cp_op : coverpoint op_code {
        bins idle = {2'b00};
        bins rd   = {2'b01};
        bins wr   = {2'b10};
        bins rw   = {2'b11};
      }

      // -----------------------------------------
      // Accepted operations
      // -----------------------------------------
      cp_wr_fire : coverpoint wr_fire {
        bins no  = {0};
        bins yes = {1};
      }

      cp_rd_fire : coverpoint rd_fire {
        bins no  = {0};
        bins yes = {1};
      }

      // -----------------------------------------
      // Error attempts
      // -----------------------------------------
      cp_overflow_attempt : coverpoint overflow_attempt {
        bins no  = {0};
        bins yes = {1};
      }

      cp_underflow_attempt : coverpoint underflow_attempt {
        bins no  = {0};
        bins yes = {1};
      }

      // -----------------------------------------
      // Occupancy regions
      // -----------------------------------------
      cp_occ : coverpoint occ_sample {
        bins empty     = {0};
        bins one       = {1};
        bins low_mid   = {[2:5]};
        bins mid       = {[6:10]};
        bins near_full = {[11:15]};
        bins full      = {16};
      }

      // -----------------------------------------
      // Flag coverage
      // -----------------------------------------
      cp_empty : coverpoint vif.cb_mon.empty {
        bins deasserted = {0};
        bins asserted   = {1};
      }

      cp_full : coverpoint vif.cb_mon.full {
        bins deasserted = {0};
        bins asserted   = {1};
      }

      // -----------------------------------------
      // Simultaneous accepted read/write
      // -----------------------------------------
      cp_sim_rw : coverpoint sim_rw {
        bins no  = {0};
        bins yes = {1};
      }

      // -----------------------------------------
      // Occupancy transitions
      // -----------------------------------------
      cp_occ_transition : coverpoint occ_sample {
        bins empty_to_nonempty = (0 => [1:16]);
        bins nonempty_to_empty = ([1:16] => 0);
        bins notfull_to_full   = ([0:15] => 16);
        bins full_to_notfull   = (16 => [0:15]);
      }

      // -----------------------------------------
      // Cross coverage
      // -----------------------------------------
      x_op_occ          : cross cp_op, cp_occ;
      x_wrfire_occ      : cross cp_wr_fire, cp_occ;
      x_rdfire_occ      : cross cp_rd_fire, cp_occ;
      x_simrw_occ       : cross cp_sim_rw, cp_occ;
      x_overflow_occ    : cross cp_overflow_attempt, cp_occ;
      x_underflow_occ   : cross cp_underflow_attempt, cp_occ;

    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap      = new("ap", this);
      cg_fifo = new();
      prev_occ = 0;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface must be set for fifo_monitor via config DB")
      void'(uvm_config_db#(int)::get(this, "", "DEPTH", DEPTH));
    endfunction

    task run_phase(uvm_phase phase);
      fifo_item obs;

      forever begin
        @(vif.cb_mon);

        if (!vif.cb_mon.rst_n) begin
          prev_occ = 0;
          continue;
        end

        // derive sampled helper signals
        op_code           = {vif.cb_mon.wr_en, vif.cb_mon.rd_en};
        wr_fire           = (vif.cb_mon.wr_en && !vif.cb_mon.full);
        rd_fire           = (vif.cb_mon.rd_en && !vif.cb_mon.empty);
        overflow_attempt  = (vif.cb_mon.wr_en && vif.cb_mon.full);
        underflow_attempt = (vif.cb_mon.rd_en && vif.cb_mon.empty);
        occ_sample        = vif.cb_mon.count;
        sim_rw            = (wr_fire && rd_fire);

        cg_fifo.sample();

        prev_occ = occ_sample;

        obs = fifo_item::type_id::create("obs");
        unique case ({vif.cb_mon.wr_en, vif.cb_mon.rd_en})
          2'b00: obs.act = ACT_IDLE;
          2'b01: obs.act = ACT_READ;
          2'b10: obs.act = ACT_WRITE;
          default: obs.act = ACT_RW;
        endcase
        obs.data = vif.cb_mon.wdata;
        ap.write(obs);
      end
    endtask
  endclass

  // =========================================================
  // Scoreboard
  // =========================================================
  class fifo_scoreboard extends uvm_component;
    `uvm_component_utils(fifo_scoreboard)

    virtual fifo_if vif;
    byte unsigned q[$];

    int unsigned pass_cnt, fail_cnt;
    bit           pending_read;
    byte unsigned pending_exp;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface must be set for fifo_scoreboard via config DB")
    endfunction

    function int unsigned get_expected_depth();
      return q.size();
    endfunction

    task run_phase(uvm_phase phase);
      pass_cnt      = 0;
      fail_cnt      = 0;
      pending_read  = 0;
      pending_exp   = '0;
      q.delete();

      forever begin
        @(posedge vif.clk);

        if (!vif.rst_n) begin
          q.delete();
          pending_read = 0;
          continue;
        end

        // compare prior accepted read because DUT rdata is registered
        if (pending_read) begin
          if (vif.rdata !== pending_exp) begin
            fail_cnt++;
            `uvm_error("SCOREBOARD",
              $sformatf("Data mismatch. EXP=0x%0h GOT=0x%0h (q_size_now=%0d)",
                        pending_exp, vif.rdata, q.size()))
          end
          else begin
            pass_cnt++;
          end
          pending_read = 0;
        end

        // accepted write
        if (vif.wr_en && !vif.full) begin
          q.push_back(vif.wdata);
        end

        // accepted read
        if (vif.rd_en && !vif.empty) begin
          if (q.size() == 0) begin
            fail_cnt++;
            `uvm_error("SCOREBOARD",
              $sformatf("Read accepted but reference queue empty. rdata=0x%0h", vif.rdata))
          end
          else begin
            pending_exp  = q.pop_front();
            pending_read = 1;
          end
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("SCOREBOARD",
        $sformatf("PASS=%0d FAIL=%0d FINAL_Q_DEPTH=%0d", pass_cnt, fail_cnt, q.size()),
        UVM_LOW)
      if (fail_cnt != 0)
        `uvm_fatal("SCOREBOARD", "Scoreboard failures detected")
    endfunction
  endclass

  // =========================================================
  // Agent
  // =========================================================
  class fifo_agent extends uvm_component;
    `uvm_component_utils(fifo_agent)

    fifo_sequencer seqr;
    fifo_driver    drv;
    fifo_monitor   mon;

    virtual fifo_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface must be set for fifo_agent via config DB")

      seqr = fifo_sequencer::type_id::create("seqr", this);
      drv  = fifo_driver   ::type_id::create("drv",  this);
      mon  = fifo_monitor  ::type_id::create("mon",  this);

      uvm_config_db#(virtual fifo_if)::set(this, "drv", "vif", vif);
      uvm_config_db#(virtual fifo_if)::set(this, "mon", "vif", vif);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  // =========================================================
  // Env
  // =========================================================
  class fifo_env extends uvm_env;
    `uvm_component_utils(fifo_env)

    fifo_agent      agt;
    fifo_scoreboard scb;

    virtual fifo_if vif;
    int DEPTH = 16;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface must be set for fifo_env via config DB")

      void'(uvm_config_db#(int)::get(this, "", "DEPTH", DEPTH));

      agt = fifo_agent     ::type_id::create("agt", this);
      scb = fifo_scoreboard::type_id::create("scb", this);

      uvm_config_db#(virtual fifo_if)::set(this, "agt", "vif", vif);
      uvm_config_db#(virtual fifo_if)::set(this, "scb", "vif", vif);
      uvm_config_db#(int)::set(this, "agt.mon", "DEPTH", DEPTH);
    endfunction
  endclass

  // =========================================================
  // Base sequence helpers
  // =========================================================
  class fifo_base_seq extends uvm_sequence #(fifo_item);
    `uvm_object_utils(fifo_base_seq)

    function new(string name = "fifo_base_seq");
      super.new(name);
    endfunction

    task send_item(fifo_act_e act, bit [7:0] data = '0);
      fifo_item it;
      it = fifo_item::type_id::create("it");
      start_item(it);
      it.act  = act;
      it.data = data;
      finish_item(it);
    endtask

    task do_idle(int n = 1);
      repeat (n) send_item(ACT_IDLE, '0);
    endtask

    task do_write(bit [7:0] data);
      send_item(ACT_WRITE, data);
    endtask

    task do_read();
      send_item(ACT_READ, '0);
    endtask

    task do_rw(bit [7:0] data);
      send_item(ACT_RW, data);
    endtask
  endclass

  // =========================================================
  // Directed sequences
  // =========================================================
  class fifo_smoke_seq extends fifo_base_seq;
    `uvm_object_utils(fifo_smoke_seq)
    int N = 8;

    function new(string name = "fifo_smoke_seq");
      super.new(name);
    endfunction

    task body();
      int i;
      for (i = 0; i < N; i++) do_write(i);
      do_idle(2);
      for (i = 0; i < N; i++) do_read();
      do_idle(4);
    endtask
  endclass

  class fifo_empty_read_seq extends fifo_base_seq;
    `uvm_object_utils(fifo_empty_read_seq)

    function new(string name = "fifo_empty_read_seq");
      super.new(name);
    endfunction

    task body();
      do_idle(2);
      repeat (5) do_read();
      do_idle(4);
    endtask
  endclass

  class fifo_full_write_seq extends fifo_base_seq;
    `uvm_object_utils(fifo_full_write_seq)
    int DEPTH = 16;

    function new(string name = "fifo_full_write_seq");
      super.new(name);
    endfunction

    task body();
      int i;
      for (i = 0; i < DEPTH; i++) do_write(8'hA0 + i);
      do_idle(2);
      do_write(8'hEE);
      do_idle(2);
      for (i = 0; i < DEPTH; i++) do_read();
      do_idle(4);
    endtask
  endclass

  class fifo_simultaneous_rw_seq extends fifo_base_seq;
    `uvm_object_utils(fifo_simultaneous_rw_seq)

    function new(string name = "fifo_simultaneous_rw_seq");
      super.new(name);
    endfunction

    task body();
      int i;

      for (i = 0; i < 6; i++) do_write(8'h10 + i);
      do_idle(2);

      for (i = 0; i < 10; i++) do_rw(8'h80 + i);
      do_idle(2);

      repeat (12) do_read();
      do_idle(4);
    endtask
  endclass

  class fifo_wraparound_seq extends fifo_base_seq;
    `uvm_object_utils(fifo_wraparound_seq)

    function new(string name = "fifo_wraparound_seq");
      super.new(name);
    endfunction

    task body();
      int i;

      for (i = 0; i < 12; i++) do_write(8'h20 + i);
      do_idle(2);

      for (i = 0; i < 8; i++) do_read();
      do_idle(2);

      for (i = 0; i < 10; i++) do_write(8'h60 + i);
      do_idle(2);

      repeat (20) do_read();
      do_idle(4);
    endtask
  endclass

  class fifo_random_seq extends fifo_base_seq;
    `uvm_object_utils(fifo_random_seq)
    rand int unsigned n_cycles;

    constraint c_cycles { n_cycles inside {[200:1000]}; }

    function new(string name = "fifo_random_seq");
      super.new(name);
    endfunction

    task body();
      fifo_item it;
      repeat (n_cycles) begin
        it = fifo_item::type_id::create("it");
        assert(it.randomize());
        start_item(it);
        finish_item(it);
      end
    endtask
  endclass

  class fifo_drain_seq extends fifo_base_seq;
    `uvm_object_utils(fifo_drain_seq)
    int max_reads = 64;

    function new(string name = "fifo_drain_seq");
      super.new(name);
    endfunction

    task body();
      repeat (max_reads) do_read();
      do_idle(4);
    endtask
  endclass

  // =========================================================
  // Base test
  // =========================================================
  class fifo_base_test extends uvm_test;
    `uvm_component_utils(fifo_base_test)

    fifo_env        env;
    virtual fifo_if vif;
    int DEPTH = 16;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface must be set for fifo_base_test via config DB")

      void'(uvm_config_db#(int)::get(this, "", "DEPTH", DEPTH));

      env = fifo_env::type_id::create("env", this);
      uvm_config_db#(virtual fifo_if)::set(this, "env", "vif", vif);
      uvm_config_db#(int)::set(this, "env", "DEPTH", DEPTH);
    endfunction

    task wait_post_seq(int n = 20);
      repeat (n) @(posedge vif.clk);
    endtask

    task wait_until_empty(int max_cycles = 200);
      int cycles;
      cycles = 0;
      while ((vif.empty !== 1'b1) && (cycles < max_cycles)) begin
        @(posedge vif.clk);
        cycles++;
      end

      if (vif.empty !== 1'b1) begin
        `uvm_fatal("DRAIN_TIMEOUT",
          $sformatf("FIFO did not become empty within %0d cycles", max_cycles))
      end
    endtask
  endclass

  // =========================================================
  // Tests
  // =========================================================
  class fifo_smoke_test extends fifo_base_test;
    `uvm_component_utils(fifo_smoke_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_smoke_seq seq;
      phase.raise_objection(this);

      wait (vif.rst_n === 1'b1);
      repeat (5) @(posedge vif.clk);

      seq = fifo_smoke_seq::type_id::create("seq");
      seq.start(env.agt.seqr);

      wait_post_seq(20);
      phase.drop_objection(this);
    endtask
  endclass

  class fifo_empty_read_test extends fifo_base_test;
    `uvm_component_utils(fifo_empty_read_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_empty_read_seq seq;
      phase.raise_objection(this);

      wait (vif.rst_n === 1'b1);
      repeat (5) @(posedge vif.clk);

      seq = fifo_empty_read_seq::type_id::create("seq");
      seq.start(env.agt.seqr);

      wait_post_seq(20);
      phase.drop_objection(this);
    endtask
  endclass

  class fifo_full_write_test extends fifo_base_test;
    `uvm_component_utils(fifo_full_write_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_full_write_seq seq;
      phase.raise_objection(this);

      wait (vif.rst_n === 1'b1);
      repeat (5) @(posedge vif.clk);

      seq = fifo_full_write_seq::type_id::create("seq");
      seq.DEPTH = DEPTH;
      seq.start(env.agt.seqr);

      wait_post_seq(25);
      phase.drop_objection(this);
    endtask
  endclass

  class fifo_simultaneous_rw_test extends fifo_base_test;
    `uvm_component_utils(fifo_simultaneous_rw_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_simultaneous_rw_seq seq;
      phase.raise_objection(this);

      wait (vif.rst_n === 1'b1);
      repeat (5) @(posedge vif.clk);

      seq = fifo_simultaneous_rw_seq::type_id::create("seq");
      seq.start(env.agt.seqr);

      wait_post_seq(25);
      phase.drop_objection(this);
    endtask
  endclass

  class fifo_wraparound_test extends fifo_base_test;
    `uvm_component_utils(fifo_wraparound_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_wraparound_seq seq;
      phase.raise_objection(this);

      wait (vif.rst_n === 1'b1);
      repeat (5) @(posedge vif.clk);

      seq = fifo_wraparound_seq::type_id::create("seq");
      seq.start(env.agt.seqr);

      wait_post_seq(30);
      phase.drop_objection(this);
    endtask
  endclass

  class fifo_random_test extends fifo_base_test;
    `uvm_component_utils(fifo_random_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_random_seq seq;
      fifo_drain_seq  drain_seq;
      int expected_depth_after_random;

      phase.raise_objection(this);

      wait (vif.rst_n === 1'b1);
      repeat (5) @(posedge vif.clk);

      seq = fifo_random_seq::type_id::create("seq");
      assert(seq.randomize() with { n_cycles == 800; });
      seq.start(env.agt.seqr);

      wait_post_seq(10);

      expected_depth_after_random = env.scb.get_expected_depth();

      `uvm_info("DRAIN",
        $sformatf("Starting drain phase. Outstanding expected FIFO depth = %0d",
                  expected_depth_after_random),
        UVM_LOW)

      drain_seq = fifo_drain_seq::type_id::create("drain_seq");
      drain_seq.max_reads = (expected_depth_after_random + DEPTH + 8);
      drain_seq.start(env.agt.seqr);

      wait_until_empty(300);
      wait_post_seq(10);

      phase.drop_objection(this);
    endtask
  endclass

endpackage