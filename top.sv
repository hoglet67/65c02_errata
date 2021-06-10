`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 06/03/2021 07:56:28 PM
// Design Name:
// Module Name: top
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

// `define USE_ALAND_CORE

module top
  (
   input         clk,
   input         acia_clk,
   input         reset,
   input         cts,
   input         rxd, // in to UART
   input         via_ca1,
   inout [7:0]   data_io,
   inout [7:0]   via_port_a,
   inout [7:0]   via_port_b,
   inout         via_ca2,
   inout         via_cb1,
   inout         via_cb2,
// output [15:0] address,
   output        rwb,
   output        sync,
   output        phi2,
   output        led_a,
   output        resb,
   output        txd, // out from UART
   output        rts
   );

   // Clock-enable counter size - the CPU runs at:
   //    system clock rate / (2 ** CLKEN_BITS)
   parameter CLKEN_BITS = 2;

   // RAM/ROM sizing
   parameter RAM_ADDR_BITS = 15;   // 32K
   parameter ROM_ADDR_BITS = 14;   // 16K

   localparam RAM_END = 2**RAM_ADDR_BITS;
   localparam ROM_START = 65536-2**ROM_ADDR_BITS;

   // Clock Enable signals
   reg [CLKEN_BITS-1:0] clken_ctr = 0;
   reg               cpu_clken; // Clock enable for the CPU
   reg               per_clken; // Clock enable for the VIA/ACIA

   // CPU signals
   wire [7:0]        cpu_din;

   // RAM signals
   wire              ram_e;
   wire [7:0]        ram_dout;

   // ROM signals
   wire              rom_e;
   wire [7:0]        rom_dout;

   // ACIA signals
   wire              acia_e;
   wire              acia_csb;
   wire [7:0]        acia_dout;

   // VIA signals
   wire              via_e;
   wire [7:0]        via_dout;
   reg  [7:0]        via_dout_r;

   wire              via_ca2_in;
   wire              via_ca2_out;
   wire              via_ca2_oe_n;
   wire [7:0]        via_pa_in;
   wire [7:0]        via_pa_out;
   wire [7:0]        via_pa_oe_n;
   wire              via_cb1_in;
   wire              via_cb1_out;
   wire              via_cb1_oe_n;
   wire              via_cb2_in;
   wire              via_cb2_out;
   wire              via_cb2_oe_n;
   wire [7:0]        via_pb_in;
   wire [7:0]        via_pb_out;
   wire [7:0]        via_pb_oe_n;

   // ========================================================
   // Clock Enable Generation
   // (currently active one in four cycles)
   // ========================================================

   // Note: this block does not use a reset to ensure everything
   // keeps being clocked when reset is asserted.
   always @(posedge clk) begin
      clken_ctr <= clken_ctr + 1'b1;
      cpu_clken <= &clken_ctr; // active when all 1's
      per_clken <= cpu_clken;  // one cycle later than the CPU
   end

`ifdef USE_ALAND_CORE

   // ========================================================
   // 65C02: Alan D's VHDL Core
   // (cycle accurate, good for tracing using the 6502 Decoder)
   // ========================================================

   wire [15:0] cpu_addr;
   wire [7:0]  cpu_dout;
   wire        cpu_nwe;
   wire        cpu_we;

   R65C02 cpu_alpha
     (
      .clk(clk),               // system clock
      .reset(!reset),           // reset
      .enable(cpu_clken),
      .nmi_n(1'b1),
      .irq_n(1'b1),
      .di(cpu_din),
      .do(cpu_dout),
      .addr(cpu_addr),
      .nwe(cpu_nwe),
      .sync(sync),
      .sync_irq(),
      .Regs()
      );

   assign cpu_we = !cpu_nwe;

`else

   // ========================================================
   // 65C02: Arlet's Verilog Core
   // (not cycle accurate)
   // ========================================================

   wire [15:0] cpu_addr_next;
   wire [7:0]  cpu_dout_next;
   wire        cpu_we_next;
   reg [15:0]  cpu_addr;
   reg [7:0]   cpu_dout;
   reg         cpu_we;

   // Note, the AB, DO and WE  outputs are one early (compared
   // to a normal 6502). Avoid using them directly unless you
   // really understand how they work.
   cpu_65c02 cpu_alpha
     (
       .clk(clk),               // system clock
       .reset(reset),           // reset
       .AB(cpu_addr_next),      // address bus (early)
       .DI(cpu_din),            // data bus input
       .DO(cpu_dout_next),      // data bus output (early)
       .WE(cpu_we_next),        // write enable (early)
       .IRQ(1'b0),              // interrupt request
       .NMI(1'b0),              // non-maskable interrupt request
       .SYNC(sync),
       .RDY(cpu_clken)          // RSY is used as a synchronous clock enable
       );

   // Register the early outputs to give a standard 6502 interface
   // (Everything else should use these registered versions)
   always @(posedge clk) begin
       if (cpu_clken) begin
           cpu_addr <= cpu_addr_next;
           cpu_dout <= cpu_dout_next;
           cpu_we   <= cpu_we_next;
       end
   end

`endif

   // CPU data input mux, default to the external bus if
   // nothing internal is selected.
   assign cpu_din = ram_e  ? ram_dout   :
                    rom_e  ? rom_dout   :
                    acia_e ? acia_dout  :
                    via_e  ? via_dout_r :
                    data_io;

   // ========================================================
   // RAM
   // ========================================================

   assign ram_e = (cpu_addr < RAM_END);

   generic_ram
     #(
       .ADDR_BITS(RAM_ADDR_BITS)
     )
     main_ram
     (
      .clk(clk),
      .ena(1'b1), // always enabled
      .wea(ram_e && cpu_we && cpu_clken),
      .addr(cpu_addr[RAM_ADDR_BITS-1:0]),
      .din(cpu_dout),
      .dout(ram_dout)
     );

   // ========================================================
   // ROM
   // ========================================================

   assign rom_e = (cpu_addr >= ROM_START);

   // ROM is now a submodule again, as this appears
   // to avoid a Vivado optimization bug when we
   // it was directly inferred here.
   generic_ram
     #(
       .ADDR_BITS(ROM_ADDR_BITS),
       .INIT_FILE("rtest_hex.txt")
     )
     main_rom
     (
      .clk(clk),
      .ena(1'b1), // always enabled
      .wea(1'b0),
      .addr(cpu_addr[ROM_ADDR_BITS-1:0]),
      .din(8'b0),
      .dout(rom_dout)
     );

   // ========================================================
   // ACIA
   // ========================================================

   assign acia_e = (cpu_addr >= 16'h8000 && cpu_addr <= 16'h800F);

   // Include cpu_clken here to avoid muptiple accesses
   assign acia_csb = !(acia_e && per_clken);

   ACIA ACIA_a
     (
      .RESET(resb),         //: in     std_logic;
      .PHI2(!clk),          //: in     std_logic;
      .CS(acia_csb),        //: in     std_logic;
      .RWN(!cpu_we),        //: in     std_logic;
      .RS(cpu_addr[1:0]),   //: in     std_logic_vector(1 downto 0);
      .DATAIN(cpu_dout),    //: in     std_logic_vector(7 downto 0);
      .DATAOUT(acia_dout),  //: out    std_logic_vector(7 downto 0);
      .XTLI(acia_clk),      //: in     std_logic;
      .RTSB(rts),           //: out    std_logic;
      .CTSB(cts),           //: in     std_logic;
      .DTRB(),              //: out    std_logic;
      .RXD(rxd),            //: in     std_logic;
      .TXD(txd),            //: buffer std_logic;
      .IRQn()               //: buffer std_logic
      );

   // ========================================================
   // VIA
   // ========================================================

   assign via_e = (cpu_addr >= 16'h8800 && cpu_addr <= 16'h880F);

   m6522 via_alpha
     (
      .CLK(clk),
      .RESET_L(resb),
      .I_P2_H(per_clken),        // clock enable for CPU interface
      .ENA_4(1'b1),              // clock enable for counters/timers
      .I_RS(cpu_addr[3:0]),
      .I_DATA(cpu_dout),
      .O_DATA(via_dout),
      .O_DATA_OE_L(),
      .I_RW_L(!cpu_we),
      .I_CS1(via_e),
      .I_CS2_L(1'b0),
      .O_IRQ_L(), // not open drain
      // port a
      .I_CA1(via_ca1),
      .I_CA2(via_ca2_in),
      .O_CA2(via_ca2_out),
      .O_CA2_OE_L(via_ca2_oe_n),
      .I_PA(via_pa_in),
      .O_PA(via_pa_out),
      .O_PA_OE_L(via_pa_oe_n),
      // port b
      .I_CB1(via_cb1_in),
      .O_CB1(via_cb1_out),
      .O_CB1_OE_L(via_cb1_oe_n),
      .I_CB2(via_cb2_in),
      .O_CB2(via_cb2_out),
      .O_CB2_OE_L(via_cb2_oe_n),
      .I_PB(via_pb_in),
      .O_PB(via_pb_out),
      .O_PB_OE_L(via_pb_oe_n)
      );

   always @(posedge clk) begin
      if (per_clken) begin
         via_dout_r <= via_dout;
      end
   end


   assign via_port_a = (!via_pa_oe_n) ? via_pa_out : 8'hZZ;
   assign via_pa_in = via_port_a;

   assign via_port_b = (!via_pb_oe_n) ? via_pb_out : 8'hZZ;
   assign via_pb_in = via_port_b;

   assign via_ca2 = (!via_ca2_oe_n) ? via_ca2_out : 1'bZ;
   assign via_ca2_in = via_ca2;

   assign via_cb2 = (!via_cb2_oe_n) ? via_cb2_out : 1'bZ;
   assign via_cb2_in = via_cb2;

   assign via_cb1 = (!via_cb1_oe_n) ? via_cb1_out : 1'bZ;
   assign via_cb1_in = via_cb1;

   // ========================================================
   // External bus interface
   // ========================================================

   assign phi2 = clken_ctr[CLKEN_BITS-1];

   assign resb = !reset;

   assign rwb = !cpu_we;

   // TODO: ideally this should be visible externally
   // assign address = cpu_addr;

   // Reads default to the external bus when no other enable matches
   assign bus_e = (!rom_e && !ram_e && !acia_e && !via_e);

   assign data_io  = cpu_we ? cpu_dout :
                     bus_e  ? 8'hZZ    :
                     cpu_din;

   // ========================================================
   // Miscellaneous
   // ========================================================

   assign led_a = !reset;

endmodule
