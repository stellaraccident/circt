// RUN: circt-opt -lower-handshake-to-firrtl %s | FileCheck %s

// CHECK-LABEL: firrtl.module @handshake_branch_1ins_1outs_ui64(
// CHECK-SAME: %arg0: !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>, %arg1: !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) {
// CHECK:   %0 = firrtl.subfield %arg0("valid") : (!firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>) -> !firrtl.uint<1>
// CHECK:   %1 = firrtl.subfield %arg0("ready") : (!firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>) -> !firrtl.uint<1>
// CHECK:   %2 = firrtl.subfield %arg0("data") : (!firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>) -> !firrtl.uint<64>
// CHECK:   %3 = firrtl.subfield %arg1("valid") : (!firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) -> !firrtl.uint<1>
// CHECK:   %4 = firrtl.subfield %arg1("ready") : (!firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) -> !firrtl.uint<1>
// CHECK:   %5 = firrtl.subfield %arg1("data") : (!firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) -> !firrtl.uint<64>
// CHECK:   firrtl.connect %3, %0 : !firrtl.uint<1>, !firrtl.uint<1>
// CHECK:   firrtl.connect %1, %4 : !firrtl.uint<1>, !firrtl.uint<1>
// CHECK:   firrtl.connect %5, %2 : !firrtl.uint<64>, !firrtl.uint<64>
// CHECK: }

// CHECK-LABEL: firrtl.module @test_branch(
// CHECK-SAME:  %arg0: !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>, %arg1: !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>>, %arg2: !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>, %arg3: !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>>>, %clock: !firrtl.clock, %reset: !firrtl.uint<1>) {
handshake.func @test_branch(%arg0: index, %arg1: none, ...) -> (index, none) {

  // CHECK: %inst_arg0, %inst_arg1 = firrtl.instance @handshake_branch_1ins_1outs_ui64  {name = ""} : !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>, !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>
  %0 = "handshake.branch"(%arg0) {control = false}: (index) -> index
  handshake.return %0, %arg1 : index, none
}
