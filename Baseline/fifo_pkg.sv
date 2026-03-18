package fifo_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum bit [1:0] {
    ACT_IDLE  = 2'b00,
    ACT_READ  = 2'b01,
    ACT_WRITE = 2'b10,
    ACT_RW    = 2'b11
  } fifo_act_e;

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

  class fifo_sequencer extends uvm_sequencer #(fifo_item);
    `uvm_component_utils(fifo_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

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

  class fifo_monitor extends uvm_component;
    `uvm_component_utils(fifo_monitor)

    virtual fifo_if vif;
    uvm_analysis_port #(fifo_item) ap;
    int DEPTH = 16;

    covergroup cg_fifo;
      option.per_instance = 1;

      cp_act : coverpoint {vif.cb_mon.wr_en, vif.cb_mon.rd_en} {
        bins idle = {2'b00};
        bins rd   = {2'b01};
        bins wr   = {2'b10};
        bins rw   = {2'b11};
      }

      cp_empty : coverpoint vif.cb_mon.empty { bins e0 = {0}; bins e1 = {1}; }
      cp_full  : coverpoint vif.cb_mon.full  { bins f0 = {0}; bins f1 = {1}; }

      cp_count : coverpoint vif.cb_mon.count {
        bins c0    = {0};
        bins c1    = {1};
        bins cmid  = {[2:13]};
        bins c14   = {14};
        bins c15   = {15};
        bins c16   = {16};
      }

      x_boundary : cross cp_act, cp_empty, cp_full;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
      cg_fifo = new();
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

        if (!vif.cb_mon.rst_n)
          continue;

        cg_fifo.sample();

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

        
        if (vif.wr_en && !vif.full) begin
          q.push_back(vif.wdata);
        end

        
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

  class fifo_base_seq extends uvm_sequence #(fifo_item);
    `uvm_object_utils(fifo_base_seq)
    function new(string name = "fifo_base_seq");
      super.new(name);
    endfunction
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

  class fifo_test extends uvm_test;
    `uvm_component_utils(fifo_test)

    fifo_env        env;
    virtual fifo_if vif;
    int DEPTH = 16;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface must be set for fifo_test via config DB")

      void'(uvm_config_db#(int)::get(this, "", "DEPTH", DEPTH));

      env = fifo_env::type_id::create("env", this);
      uvm_config_db#(virtual fifo_if)::set(this, "env", "vif", vif);
      uvm_config_db#(int)::set(this, "env", "DEPTH", DEPTH);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_random_seq seq;

      phase.raise_objection(this);

      wait (vif.rst_n === 1'b1);
      repeat (5) @(posedge vif.clk);

      seq = fifo_random_seq::type_id::create("seq");
      assert(seq.randomize() with { n_cycles == 800; });
      seq.start(env.agt.seqr);

      
      repeat (60) @(posedge vif.clk);

      phase.drop_objection(this);
    endtask
  endclass

endpackage