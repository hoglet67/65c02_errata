`timescale 1ns/1ns

// 50MHz System Clock
`define T_clock 20

// 1.8432MHz ACIA Clock
`define T_acia_clock 542

module top_tb;

   // This just contains a reset vector pointing to $3400
   parameter ROM_IMAGE = "null_rom.hex";

   // The Dormann tests have been compiled to run at $3400
   parameter RAM_IMAGE = "dormann_6502.hex";
   // parameter RAM_IMAGE = "dormann_65c02.hex";

   reg clk;
   reg reset;
   reg acia_clk;
   reg rxd;
   reg cts;

   wire txd;
   wire rts;

   wire [7:0] data_io;

   wire [15:0] address;
   wire        rwb;
   wire        phi2;
   wire        led_a;
   wire        resb;
   wire        sync;

   reg [7:0]   write_data = 8'hZZ;

   wire        acia_select;

   wire [7:0]  via_port_a;
   wire [7:0]  via_port_b;
   reg         via_ca1;
   wire        via_ca2;
   wire        via_cb1;
   wire        via_cb2;
   integer     trace_fd;

   initial  begin
      trace_fd=$fopen("trace.hex", "w");
      //$dumpvars();
      // ACIA
      acia_clk   = 1'b0;
      rxd   = 1'b1;
      cts   = 1'b0;
      // VIA
      via_ca1 = 1'b0;
      // 6502
      clk   = 1'b0;
      reset = 1'b0;
      repeat(10) begin
         @(posedge clk);
      end
      reset = 1'b1;
      repeat(10) begin
         @(posedge clk);
      end
      reset = 1'b0;
      //#(`T_clock * 1000000)
      //$finish;
   end

   always @(negedge phi2) begin
      $fwrite(trace_fd, "%h\n", {data_io, 6'b111111, sync, rwb});
   end


   always #(`T_clock / 2) begin
      clk = ~clk;
   end

   always #(`T_acia_clock / 2) begin
      acia_clk = ~acia_clk;
   end

   assign address = top.cpu_addr;

   assign  acia_select = ({address[15:2] , 2'b0} == 16'h8000);

   always @(negedge phi2) begin
      if (!rwb && acia_select && address[1:0] == 2'b00) begin
         $display("%x %c", data_io, data_io);
      end
   end

   defparam top.CLKEN_BITS = 3;
   defparam top.main_ram.INIT_FILE = RAM_IMAGE;
   defparam top.main_rom.INIT_FILE = ROM_IMAGE;

   // Unit under test
   top top
     (
      // System Clock
      .clk(clk),

      // Reset in (active high)
      .reset(reset),

      // External 6502 bus interface
      .phi2(phi2),
      .resb(resb),
      .sync(sync),
      //.address(address),
      .rwb(rwb),
      .data_io(data_io),

      // ACIA
      .acia_clk(acia_clk),
      .rxd(rxd),
      .cts(cts),
      .txd(txd),
      .rts(rts),

      // VIA
      .via_port_a(via_port_a),
      .via_port_b(via_port_b),
      .via_ca1(via_ca1),
      .via_ca2(via_ca2),
      .via_cb1(via_cb1),
      .via_cb2(via_cb2),

      // Miscellaneous
      .led_a(led_a)
      );

endmodule
