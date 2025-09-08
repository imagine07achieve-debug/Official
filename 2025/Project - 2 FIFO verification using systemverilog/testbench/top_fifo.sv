`timescale 1ns / 1ps
//another file
//bhai
//fun
//transaction module 1
class transaction;
  //only input signals for randomisation and no ports
  bit rst,clk;
  rand bit [31:0] data_in;
  rand bit wr_en,rd_en;	
  bit[31:0]data_op;
  bit full,empty;
  
  constraint wr_rd_en{wr_en != rd_en;};

endclass



//interface module 2
interface fifo_intf(input logic clk,rst);
  logic [31:0]data_in;
  logic wr_en,rd_en;
  logic [31:0]data_op;
  logic full,empty;
  
  clocking driver_cb@(posedge clk);
    default input #1 output #1;
    output data_in;
    output wr_en,rd_en;
    input data_op;
    input full,empty;
  endclocking

  clocking monitor_cb@(posedge clk);
    default input #1 output #1;
    input data_in;
    input wr_en,rd_en;
    input data_op;
    input full,empty;
  endclocking
  
  modport DRIVER(clocking driver_cb,input clk,rst);
  modport MONITOR(clocking monitor_cb,input clk,rst);
    
endinterface  



//generator module 3
class generator;
  //declaring transaction class 
  rand transaction trans;
  mailbox gen2drv;
  int repeat_count;
  event drv2gen;

  function new( mailbox gen2drv, event drv2gen);
    this.gen2drv = gen2drv;
    this.drv2gen = drv2gen;  
  endfunction
  
  task main();
   repeat(repeat_count)begin 
    trans = new();
    if(!trans.randomize()) $fatal("Gen::trans randomization failed"); 
     gen2drv.put(trans);
   end 
   ->drv2gen;
  endtask

endclass



//driver module 4
`define DRIVER_IF fifo_intf.DRIVER.driver_cb
//DRIVER_IF ponts to the DRIVER modport in interface
class driver;
  
  int no_trans;
  virtual fifo_intf vif_fifo;
  mailbox gen2drv;
  
  function new(virtual fifo_intf vif_fifo,mailbox gen2drv);
    this.vif_fifo = vif_fifo;
    this.gen2drv = gen2drv;
  endfunction  
  
  task reset;
    $display("resetting");
    wait(vif_fifo.rst);
    `DRIVER_IF.data_in <= 0;
    `DRIVER_IF.wr_en <= 0;
    `DRIVER_IF.rd_en <= 0;
    wait(!vif_fifo.rst);
    $display("done resetting");
  endtask
  
  task drive;
    forever begin
      transaction trans;
     `DRIVER_IF.wr_en <=0;
     `DRIVER_IF.rd_en <=0;
     gen2drv.get(trans);
     $display("no: of transactions = ",no_trans);
     
     @(posedge vif_fifo.clk);
     if(trans.wr_en)begin
      `DRIVER_IF.wr_en <= trans.wr_en;
      `DRIVER_IF.data_in <= trans.data_in;
       trans.full =`DRIVER_IF.full;
       trans.empty =`DRIVER_IF.empty;
      $display("\t write enable = %0h \t data input = %0h",trans.wr_en,trans.data_in);
     end
     
     if(trans.rd_en)begin
      `DRIVER_IF.rd_en <= trans.rd_en;
       @(posedge vif_fifo.clk);
      `DRIVER_IF.rd_en <= 0;
      @(posedge vif_fifo.clk);
       trans.data_op =`DRIVER_IF.data_op  ;
       trans.full = `DRIVER_IF.full;
       trans.empty =`DRIVER_IF.empty;

      $display("\t read enable = %0h \t data output = %0h",trans.rd_en,trans.data_op);
     end
    no_trans++;
    end
  endtask
  
  task main;
   
   forever begin
    fork 
     begin
      wait(vif_fifo.rst);
     end
    
     begin
      drive();
     end
    join_any
    disable fork;
   end
  endtask
    
endclass



//monitor module 5
`define MONITOR_IF fifo_intf.MONITOR.monitor_cb
class monitor; 
 virtual fifo_intf vif_fifo;
 mailbox mon2scb;
 
 function new(virtual fifo_intf vif_fifo,mailbox mon2scb);
  this.vif_fifo = vif_fifo;
  this.mon2scb = mon2scb;
 endfunction
 
 task main;
  forever begin
   transaction trans;
   trans = new();
   @(posedge vif_fifo.clk);
   wait(`MONITOR_IF.wr_en||`MONITOR_IF.rd_en);
   if(`MONITOR_IF.wr_en)begin
    trans.wr_en = `MONITOR_IF.wr_en ;
    trans.data_in = `MONITOR_IF.data_in; 
    trans.full = `MONITOR_IF.full;
    trans.empty = `MONITOR_IF.empty;
    $display("\t ADDR= %0h \t DATA IN = %0h",trans.wr_en,trans.data_in);
   end
   @(posedge vif_fifo.clk);
   if(`MONITOR_IF.rd_en)begin
    trans.rd_en = `MONITOR_IF.rd_en ;
    @(posedge vif_fifo.clk);
     trans.data_op = `MONITOR_IF.data_op;
     trans.full = `MONITOR_IF.full;
     trans.empty = `MONITOR_IF.empty;
    $display("\t ADDR= %0h \t DATA IN = %0h",trans.wr_en,trans.data_in);
   end
   mon2scb.put(trans);
  end   
 endtask
endclass



//scoreboard module 6
class scoreboard;
 mailbox mon2scb;
 int no_trans;
 //bit[7:0]ram[4];
 //bit wr_ptr;
 //bit rd_ptr;
 bit [31:0] ram[0:31];  // match FIFO width and depth
int wr_ptr, rd_ptr;    // increase from 1-bit to full index

 function new(mailbox mon2scb);
   this.mon2scb = mon2scb;
   foreach(ram[i])begin
    ram[i] = 8'hff;
   end
 endfunction 
 
  task main;
   forever begin   
    transaction trans;
    #50
    mon2scb.get(trans);
    if(trans.wr_en)begin
      ram[wr_ptr] = trans.data_in;
      wr_ptr++;
    end  
    if(trans.rd_en)begin
      if(trans.data_op == ram[rd_ptr])begin
        rd_ptr++;
        $display("yup");
      end
      else begin
        $display("nop");
      end
    end
    if(trans.full)begin
      $display("fifo is full");
    end
    if(trans.empty)begin
      $display("fifo is empty");
    end
    no_trans++;
   end
  endtask
endclass



//environment module 7
class environment;
  
  generator gen;
  driver drv;
  monitor mon;
  scoreboard scb;
  
  mailbox gen2drv;
  mailbox mon2scb;
  
  event drv2gen;//to show generation of signals have stopped
  virtual fifo_intf vif_fifo;
  
  function new(virtual fifo_intf vif_fifo);
    this.vif_fifo = vif_fifo;
    gen2drv = new();
    mon2scb = new();
    gen = new(gen2drv,drv2gen);
    drv = new(vif_fifo,gen2drv);
    mon = new(vif_fifo,mon2scb);
    scb = new(mon2scb);
  endfunction
  
  task pre_test();
   drv.reset();
  endtask
  
  task test();
   gen.main();
   drv.main();
   mon.main();
   scb.main();
  endtask
  
  task post_test();
   wait(drv2gen.triggered);
   wait(gen.repeat_count == drv.no_trans);
   wait(gen.repeat_count == scb.no_trans);
  endtask
  
  task run();
   pre_test();
   test();
   post_test();
   $finish;
  endtask
endclass



//test module 8
program test(fifo_intf intf);
  environment env;
  
  initial begin
    env = new(intf);
    env.gen.repeat_count = 10;
    env.run();
  end
endprogram



//testbench_top module 9
module tb_top;
 bit clk,rst;
 
 always #5 clk = ~ clk;
 
 initial begin
  clk = 0;
  rst = 1;
  #20 rst = 0;
 end
 
 fifo_intf intf(clk,rst) ;
 test t1(intf);
 fifo DUT(.data_op(intf.data_op),
          .full(intf.full),
          .empty(intf.empty),
          .data_in(intf.data_in),
          .wr_en(intf.wr_en),
          .rd_en(intf.rd_en),
          .clk(intf.clk),
          .rst(intf.rst));
endmodule







