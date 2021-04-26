# REQUIRES: bindings_python
# RUN: %PYTHON% %s | FileCheck %s

import sys

import circt
from circt.dialects import rtl, seq

from mlir.ir import *
from mlir.passmanager import PassManager

with Context() as ctx, Location.unknown():
  circt.register_dialects(ctx)

  i1 = IntegerType.get_signless(1)
  i32 = IntegerType.get_signless(32)

  # CHECK-LABEL: === MLIR ===
  m = Module.create()
  with InsertionPoint(m.body):

    @rtl.RTLModuleOp.from_py_func(i1, i1)
    def top(clk, rstn):
      # CHECK: %[[RESET_VAL:.+]] = rtl.constant 0
      reg_reset = rtl.ConstantOp(i32, IntegerAttr.get(i32, 0)).result
      # CHECK: %[[INPUT_VAL:.+]] = rtl.constant 45
      reg_input = rtl.ConstantOp(i32, IntegerAttr.get(i32, 45)).result
      # CHECK: %[[DATA_VAL:.+]] = seq.compreg %[[INPUT_VAL]], %clk, %rstn, %[[RESET_VAL]]
      reg = seq.CompRegOp(i32, reg_input, clk, rstn, reg_reset, name="my_reg")
      # CHECK: rtl.output %[[DATA_VAL]]
      return reg.data

  print("=== MLIR ===")
  print(m)

  # CHECK-LABEL: === Verilog ===
  print("=== Verilog ===")

  pm = PassManager.parse("lower-seq-to-sv")
  pm.run(m)
  # CHECK: always_ff @(posedge clk)
  # CHECK: my_reg <= {{.+}}
  circt.export_verilog(m, sys.stdout)
