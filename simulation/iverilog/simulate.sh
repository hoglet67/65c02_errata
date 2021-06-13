#!/bin/bash

SRCDIR=../..

SIM=soc65c02

rm -f dump.vcd $SIM

iverilog  -o $SIM \
          top_tb.v \
          $SRCDIR/top.sv \
          $SRCDIR/cpu_65c02.v \
          $SRCDIR/ALU.v \
          $SRCDIR/generic_ram.v \
          $SRCDIR/m6522.v \
          $SRCDIR/6551-ACIA-Verilog/*.v

if [ -f $SIM ]; then

    ./$SIM

    if [ -f dump.vcd ]; then

        gtkwave  dump.vcd top_tb.gtkw

    fi
fi
