// RUN: circt-opt -pass-pipeline='firrtl.circuit(firrtl-lower-types)' -split-input-file %s | FileCheck %s

firrtl.circuit "TopLevel" {

  // CHECK-LABEL: firrtl.module @Simple
  // CHECK-SAME: %[[SOURCE_VALID_NAME:source_valid]]: [[SOURCE_VALID_TYPE:!firrtl.uint<1>]]
  // CHECK-SAME: %[[SOURCE_READY_NAME:source_ready]]: [[SOURCE_READY_TYPE:!firrtl.flip<uint<1>>]]
  // CHECK-SAME: %[[SOURCE_DATA_NAME:source_data]]: [[SOURCE_DATA_TYPE:!firrtl.uint<64>]]
  // CHECK-SAME: %[[SINK_VALID_NAME:sink_valid]]: [[SINK_VALID_TYPE:!firrtl.flip<uint<1>>]]
  // CHECK-SAME: %[[SINK_READY_NAME:sink_ready]]: [[SINK_READY_TYPE:!firrtl.uint<1>]]
  // CHECK-SAME: %[[SINK_DATA_NAME:sink_data]]: [[SINK_DATA_TYPE:!firrtl.flip<uint<64>>]]
  firrtl.module @Simple(%source: !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>,
                        %sink: !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) {

    // CHECK-NEXT: firrtl.when %[[SOURCE_VALID_NAME]]
    // CHECK-NEXT:   firrtl.connect %[[SINK_DATA_NAME]], %[[SOURCE_DATA_NAME]] : [[SINK_DATA_TYPE]], [[SOURCE_DATA_TYPE]]
    // CHECK-NEXT:   firrtl.connect %[[SINK_VALID_NAME]], %[[SOURCE_VALID_NAME]] : [[SINK_VALID_TYPE]], [[SOURCE_VALID_TYPE]]
    // CHECK-NEXT:   firrtl.connect %[[SOURCE_READY_NAME]], %[[SINK_READY_NAME]] : [[SOURCE_READY_TYPE]], [[SINK_READY_TYPE]]

    %0 = firrtl.subfield %source("valid") : (!firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>) -> !firrtl.uint<1>
    %1 = firrtl.subfield %source("ready") : (!firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>) -> !firrtl.uint<1>
    %2 = firrtl.subfield %source("data") : (!firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>) -> !firrtl.uint<64>
    %3 = firrtl.subfield %sink("valid") : (!firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) -> !firrtl.uint<1>
    %4 = firrtl.subfield %sink("ready") : (!firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) -> !firrtl.uint<1>
    %5 = firrtl.subfield %sink("data") : (!firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) -> !firrtl.uint<64>
    firrtl.when %0 {
      firrtl.connect %5, %2 : !firrtl.uint<64>, !firrtl.uint<64>
      firrtl.connect %3, %0 : !firrtl.uint<1>, !firrtl.uint<1>
      firrtl.connect %1, %4 : !firrtl.uint<1>, !firrtl.uint<1>
    }
  }

  // CHECK-LABEL: firrtl.module @TopLevel
  // CHECK-SAME: %source_valid: [[SOURCE_VALID_TYPE:!firrtl.uint<1>]]
  // CHECK-SAME: %source_ready: [[SOURCE_READY_TYPE:!firrtl.flip<uint<1>>]]
  // CHECK-SAME: %source_data: [[SOURCE_DATA_TYPE:!firrtl.uint<64>]]
  // CHECK-SAME: %sink_valid: [[SINK_VALID_TYPE:!firrtl.flip<uint<1>>]]
  // CHECK-SAME: %sink_ready: [[SINK_READY_TYPE:!firrtl.uint<1>]]
  // CHECK-SAME: %sink_data: [[SINK_DATA_TYPE:!firrtl.flip<uint<64>>]]
  firrtl.module @TopLevel(%source: !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>,
                          %sink: !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) {

    // CHECK-NEXT: %inst_source_valid, %inst_source_ready, %inst_source_data, %inst_sink_valid, %inst_sink_ready, %inst_sink_data
    // CHECK-SAME: = firrtl.instance @Simple {name = ""} :
    // CHECK-SAME: !firrtl.flip<uint<1>>, !firrtl.uint<1>, !firrtl.flip<uint<64>>, !firrtl.uint<1>, !firrtl.flip<uint<1>>, !firrtl.uint<64>
    %sourceV, %sinkV = firrtl.instance @Simple {name = ""} : !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>, !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>

    // CHECK-NEXT: firrtl.connect %inst_source_valid, %source_valid
    // CHECK-NEXT: firrtl.connect %source_ready, %inst_source_ready
    // CHECK-NEXT: firrtl.connect %inst_source_data, %source_data
    // CHECK-NEXT: firrtl.connect %sink_valid, %inst_sink_valid
    // CHECK-NEXT: firrtl.connect %inst_sink_ready, %sink_ready
    // CHECK-NEXT: firrtl.connect %sink_data, %inst_sink_data
    firrtl.connect %sourceV, %source : !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>, !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>

    firrtl.connect %sink, %sinkV : !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>, !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>
  }
}

// -----

firrtl.circuit "Recursive" {

  // CHECK-LABEL: firrtl.module @Recursive
  // CHECK-SAME: %[[FLAT_ARG_1_NAME:arg_foo_bar_baz]]: [[FLAT_ARG_1_TYPE:!firrtl.uint<1>]]
  // CHECK-SAME: %[[FLAT_ARG_2_NAME:arg_foo_qux]]: [[FLAT_ARG_2_TYPE:!firrtl.sint<64>]]
  // CHECK-SAME: %[[OUT_1_NAME:out1]]: [[OUT_1_TYPE:!firrtl.flip<uint<1>>]]
  // CHECK-SAME: %[[OUT_2_NAME:out2]]: [[OUT_2_TYPE:!firrtl.flip<sint<64>>]]
  firrtl.module @Recursive(%arg: !firrtl.bundle<foo: bundle<bar: bundle<baz: uint<1>>, qux: sint<64>>>,
                           %out1: !firrtl.flip<uint<1>>, %out2: !firrtl.flip<sint<64>>) {

    // CHECK-NEXT: firrtl.connect %[[OUT_1_NAME]], %[[FLAT_ARG_1_NAME]] : [[OUT_1_TYPE]], [[FLAT_ARG_1_TYPE]]
    // CHECK-NEXT: firrtl.connect %[[OUT_2_NAME]], %[[FLAT_ARG_2_NAME]] : [[OUT_2_TYPE]], [[FLAT_ARG_2_TYPE]]

    %0 = firrtl.subfield %arg("foo") : (!firrtl.bundle<foo: bundle<bar: bundle<baz: uint<1>>, qux: sint<64>>>) -> !firrtl.bundle<bar: bundle<baz: uint<1>>, qux: sint<64>>
    %1 = firrtl.subfield %0("bar") : (!firrtl.bundle<bar: bundle<baz: uint<1>>, qux: sint<64>>) -> !firrtl.bundle<baz: uint<1>>
    %2 = firrtl.subfield %1("baz") : (!firrtl.bundle<baz: uint<1>>) -> !firrtl.uint<1>
    %3 = firrtl.subfield %0("qux") : (!firrtl.bundle<bar: bundle<baz: uint<1>>, qux: sint<64>>) -> !firrtl.sint<64>
    firrtl.connect %out1, %2 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    firrtl.connect %out2, %3 : !firrtl.flip<sint<64>>, !firrtl.sint<64>
  }

}

// -----

firrtl.circuit "Uniquification" {

  // CHECK-LABEL: firrtl.module @Uniquification
  // CHECK-SAME: %[[FLATTENED_ARG:a_b]]: [[FLATTENED_TYPE:!firrtl.uint<1>]],
  // CHECK-NOT: %[[FLATTENED_ARG]]
  // CHECK-SAME: %[[RENAMED_ARG:a_b.+]]: [[RENAMED_TYPE:!firrtl.uint<1>]]
  // CHECK-SAME: {portNames = ["a_b", "a_b"]}
  firrtl.module @Uniquification(%a: !firrtl.bundle<b: uint<1>>, %a_b: !firrtl.uint<1>) {
  }

}

// -----

firrtl.circuit "Top" {

  // CHECK-LABEL: firrtl.module @Top
  firrtl.module @Top(%in : !firrtl.bundle<a: uint<1>, b: uint<1>>,
                     %out : !firrtl.flip<bundle<a: uint<1>, b: uint<1>>>) {
    // CHECK: firrtl.connect %out_a, %in_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    // CHECK: firrtl.connect %out_b, %in_b : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    firrtl.connect %out, %in : !firrtl.flip<bundle<a: uint<1>, b: uint<1>>>, !firrtl.bundle<a: uint<1>, b: uint<1>>
  }

}

// -----

firrtl.circuit "Foo" {
  // CHECK-LABEL: firrtl.module @Foo
  // CHECK-SAME: %[[FLAT_ARG_INPUT_NAME:a_b_c]]: [[FLAT_ARG_INPUT_TYPE:!firrtl.uint<1>]]
  // CHECK-SAME: %[[FLAT_ARG_OUTPUT_NAME:b_b_c]]: [[FLAT_ARG_OUTPUT_TYPE:!firrtl.flip<uint<1>>]]
  firrtl.module @Foo(%a: !firrtl.bundle<b: bundle<c: uint<1>>>, %b: !firrtl.flip<bundle<b: bundle<c: uint<1>>>>) {
    // CHECK: firrtl.connect %[[FLAT_ARG_OUTPUT_NAME]], %[[FLAT_ARG_INPUT_NAME]] : [[FLAT_ARG_OUTPUT_TYPE]], [[FLAT_ARG_INPUT_TYPE]]
    firrtl.connect %b, %a : !firrtl.flip<bundle<b: bundle<c: uint<1>>>>, !firrtl.bundle<b: bundle<c: uint<1>>>
  }
}

// -----

// COM: Test lower of a 1-read 1-write aggregate memory
//
// COM: circuit Foo :
// COM:   module Foo :
// COM:     input clock: Clock
// COM:     input rAddr: UInt<4>
// COM:     input rEn: UInt<1>
// COM:     output rData: {a: UInt<8>, b: UInt<8>}
// COM:     input wAddr: UInt<4>
// COM:     input wEn: UInt<1>
// COM:     input wMask: {a: UInt<1>, b: UInt<1>}
// COM:     input wData: {a: UInt<8>, b: UInt<8>}
// COM:
// COM:     mem memory:
// COM:       data-type => {a: UInt<8>, b: UInt<8>}
// COM:       depth => 16
// COM:       reader => r
// COM:       writer => w
// COM:       read-latency => 0
// COM:       write-latency => 1
// COM:       read-under-write => undefined
// COM:
// COM:     memory.r.clk <= clock
// COM:     memory.r.en <= rEn
// COM:     memory.r.addr <= rAddr
// COM:     rData <= memory.r.data
// COM:
// COM:     memory.w.clk <= clock
// COM:     memory.w.en <= wEn
// COM:     memory.w.addr <= wAddr
// COM:     memory.w.mask <= wMask
// COM:     memory.w.data <= wData

firrtl.circuit "Foo" {

  // CHECK-LABEL: firrtl.module @Foo
  firrtl.module @Foo(%clock: !firrtl.clock, %rAddr: !firrtl.uint<4>, %rEn: !firrtl.uint<1>, %rData: !firrtl.flip<bundle<a: uint<8>, b: uint<8>>>, %wAddr: !firrtl.uint<4>, %wEn: !firrtl.uint<1>, %wMask: !firrtl.bundle<a: uint<1>, b: uint<1>>, %wData: !firrtl.bundle<a: uint<8>, b: uint<8>>) {
    %memory_r, %memory_w = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r", "w"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<bundle<a: uint<8>, b: uint<8>>>>>, !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: bundle<a: uint<8>, b: uint<8>>, mask: bundle<a: uint<1>, b: uint<1>>>>
    %0 = firrtl.subfield %memory_r("clk") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<bundle<a: uint<8>, b: uint<8>>>>>) -> !firrtl.clock
    firrtl.connect %0, %clock : !firrtl.clock, !firrtl.clock
    %1 = firrtl.subfield %memory_r("en") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<bundle<a: uint<8>, b: uint<8>>>>>) -> !firrtl.uint<1>
    firrtl.connect %1, %rEn : !firrtl.uint<1>, !firrtl.uint<1>
    %2 = firrtl.subfield %memory_r("addr") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<bundle<a: uint<8>, b: uint<8>>>>>) -> !firrtl.uint<4>
    firrtl.connect %2, %rAddr : !firrtl.uint<4>, !firrtl.uint<4>
    %3 = firrtl.subfield %memory_r("data") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<bundle<a: uint<8>, b: uint<8>>>>>) -> !firrtl.bundle<a: uint<8>, b: uint<8>>
    firrtl.connect %rData, %3 : !firrtl.flip<bundle<a: uint<8>, b: uint<8>>>, !firrtl.bundle<a: uint<8>, b: uint<8>>
    %4 = firrtl.subfield %memory_w("clk") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: bundle<a: uint<8>, b: uint<8>>, mask: bundle<a: uint<1>, b: uint<1>>>>) -> !firrtl.clock
    firrtl.connect %4, %clock : !firrtl.clock, !firrtl.clock
    %5 = firrtl.subfield %memory_w("en") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: bundle<a: uint<8>, b: uint<8>>, mask: bundle<a: uint<1>, b: uint<1>>>>) -> !firrtl.uint<1>
    firrtl.connect %5, %wEn : !firrtl.uint<1>, !firrtl.uint<1>
    %6 = firrtl.subfield %memory_w("addr") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: bundle<a: uint<8>, b: uint<8>>, mask: bundle<a: uint<1>, b: uint<1>>>>) -> !firrtl.uint<4>
    firrtl.connect %6, %wAddr : !firrtl.uint<4>, !firrtl.uint<4>
    %7 = firrtl.subfield %memory_w("mask") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: bundle<a: uint<8>, b: uint<8>>, mask: bundle<a: uint<1>, b: uint<1>>>>) -> !firrtl.bundle<a: uint<1>, b: uint<1>>
    firrtl.connect %7, %wMask : !firrtl.bundle<a: uint<1>, b: uint<1>>, !firrtl.bundle<a: uint<1>, b: uint<1>>
    %8 = firrtl.subfield %memory_w("data") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: bundle<a: uint<8>, b: uint<8>>, mask: bundle<a: uint<1>, b: uint<1>>>>) -> !firrtl.bundle<a: uint<8>, b: uint<8>>
    firrtl.connect %8, %wData : !firrtl.bundle<a: uint<8>, b: uint<8>>, !firrtl.bundle<a: uint<8>, b: uint<8>>

    // COM: ---------------------------------------------------------------------------------
    // COM: Split memory "a" should exist
    // CHECK: %[[MEMORY_A_R:.+]], %[[MEMORY_A_W:.+]] = firrtl.mem {{.+}} data: uint<8>, mask: uint<1>
    // COM: ---------------------------------------------------------------------------------
    // COM: Read port
    // CHECK-DAG: %[[MEMORY_A_R_ADDR:.+]] = firrtl.subfield %[[MEMORY_A_R]]("addr")
    // CHECK-DAG: %[[MEMORY_R_ADDR:.+]] = firrtl.wire
    // CHECK: firrtl.connect %[[MEMORY_A_R_ADDR]], %[[MEMORY_R_ADDR]]
    // CHECK-DAG: %[[MEMORY_A_R_EN:.+]] = firrtl.subfield %[[MEMORY_A_R]]("en")
    // CHECK-DAG: %[[MEMORY_R_EN:.+]] = firrtl.wire
    // CHECK: firrtl.connect %[[MEMORY_A_R_EN]], %[[MEMORY_R_EN]]
    // CHECK-DAG: %[[MEMORY_A_R_CLK:.+]] = firrtl.subfield %[[MEMORY_A_R]]("clk")
    // CHECK-DAG: %[[MEMORY_R_CLK:.+]] = firrtl.wire
    // CHECK: firrtl.connect %[[MEMORY_A_R_CLK]], %[[MEMORY_R_CLK]]
    // CHECK: %[[MEMORY_A_R_DATA:.+]] = firrtl.subfield %[[MEMORY_A_R]]("data")
    // COM: ---------------------------------------------------------------------------------
    // COM: Write Port
    // CHECK-DAG: %[[MEMORY_A_W_ADDR:.+]] = firrtl.subfield %[[MEMORY_A_W]]("addr")
    // CHECK-DAG: %[[MEMORY_W_ADDR:.+]] = firrtl.wire
    // CHECK: firrtl.connect %[[MEMORY_A_W_ADDR]], %[[MEMORY_W_ADDR]]
    // CHECK-DAG: %[[MEMORY_A_W_EN:.+]] = firrtl.subfield %[[MEMORY_A_W]]("en")
    // CHECK-DAG: %[[MEMORY_W_EN:.+]] = firrtl.wire
    // CHECK: firrtl.connect %[[MEMORY_A_W_EN]], %[[MEMORY_W_EN]]
    // CHECK-DAG: %[[MEMORY_A_W_CLK:.+]] = firrtl.subfield %[[MEMORY_A_W]]("clk")
    // CHECK-DAG: %[[MEMORY_W_CLK:.+]] = firrtl.wire
    // CHECK: firrtl.connect %[[MEMORY_A_W_CLK]], %[[MEMORY_W_CLK]]
    // CHECK: %[[MEMORY_A_W_DATA:.+]] = firrtl.subfield %[[MEMORY_A_W]]("data")
    // CHECK: %[[MEMORY_A_W_MASK:.+]] = firrtl.subfield %[[MEMORY_A_W]]("mask")
    // COM: ---------------------------------------------------------------------------------
    // COM: Split memory "b" should exist
    // CHECK: %[[MEMORY_B_R:.+]], %[[MEMORY_B_W:.+]] = firrtl.mem {{.+}} data: uint<8>, mask: uint<1>
    // COM: ---------------------------------------------------------------------------------
    // COM: Read port
    // CHECK: %[[MEMORY_B_R_ADDR:.+]] = firrtl.subfield %[[MEMORY_B_R]]("addr")
    // CHECK: firrtl.connect %[[MEMORY_B_R_ADDR]], %[[MEMORY_R_ADDR]]
    // CHECK: %[[MEMORY_B_R_EN:.+]] = firrtl.subfield %[[MEMORY_B_R]]("en")
    // CHECK: firrtl.connect %[[MEMORY_B_R_EN]], %[[MEMORY_R_EN]]
    // CHECK: %[[MEMORY_B_R_CLK:.+]] = firrtl.subfield %[[MEMORY_B_R]]("clk")
    // CHECK: firrtl.connect %[[MEMORY_B_R_CLK]], %[[MEMORY_R_CLK]]
    // CHECK: %[[MEMORY_B_R_DATA:.+]] = firrtl.subfield %[[MEMORY_B_R]]("data")
    // COM: ---------------------------------------------------------------------------------
    // COM: Write port
    // CHECK: %[[MEMORY_B_W_ADDR:.+]] = firrtl.subfield %[[MEMORY_B_W]]("addr")
    // CHECK: firrtl.connect %[[MEMORY_B_W_ADDR]], %[[MEMORY_W_ADDR]]
    // CHECK: %[[MEMORY_B_W_EN:.+]] = firrtl.subfield %[[MEMORY_B_W]]("en")
    // CHECK: firrtl.connect %[[MEMORY_B_W_EN]], %[[MEMORY_W_EN]]
    // CHECK: %[[MEMORY_B_W_CLK:.+]] = firrtl.subfield %[[MEMORY_B_W]]("clk")
    // CHECK: firrtl.connect %[[MEMORY_B_W_CLK]], %[[MEMORY_W_CLK]]
    // CHECK: %[[MEMORY_B_W_DATA:.+]] = firrtl.subfield %[[MEMORY_B_W]]("data")
    // CHECK: %[[MEMORY_B_W_MASK:.+]] = firrtl.subfield %[[MEMORY_B_W]]("mask")
    // COM: ---------------------------------------------------------------------------------
    // COM: Connections to module ports
    // CHECK: firrtl.connect %[[MEMORY_R_CLK]], %clock
    // CHECK: firrtl.connect %[[MEMORY_R_EN]], %rEn
    // CHECK: firrtl.connect %[[MEMORY_R_ADDR]], %rAddr
    // CHECK: firrtl.connect %rData_a, %[[MEMORY_A_R_DATA]]
    // CHECK: firrtl.connect %rData_b, %[[MEMORY_B_R_DATA]]
    // CHECK: firrtl.connect %[[MEMORY_W_CLK]], %clock
    // CHECK: firrtl.connect %[[MEMORY_W_EN]], %wEn
    // CHECK: firrtl.connect %[[MEMORY_W_ADDR]], %wAddr
    // CHECK: firrtl.connect %[[MEMORY_A_W_MASK]], %wMask_a
    // CHECK: firrtl.connect %[[MEMORY_B_W_MASK]], %wMask_b
    // CHECK: firrtl.connect %[[MEMORY_A_W_DATA]], %wData_a
    // CHECK: firrtl.connect %[[MEMORY_B_W_DATA]], %wData_b

  }
}

// -----

// COM: Test that a memory with a readwrite port is split into 1r1w
//
// circuit Foo:
//  module Foo:
//    input clock: Clock
//    input rwEn: UInt<1>
//    input rwMode: UInt<1>
//    input rwAddr: UInt<4>
//    input rwMask: UInt<1>
//    input rwDataIn: UInt<8>
//    output rwDataOut: UInt<8>
//
//    mem memory:
//      data-type => UInt<8>
//      depth => 16
//      readwriter => rw
//      read-latency => 0
//      write-latency => 1
//      read-under-write => undefined
//
//    memory.rw.clk <= clock
//    memory.rw.en <= rwEn
//    memory.rw.addr <= rwAddr
//    memory.rw.wmode <= rwMode
//    memory.rw.wmask <= rwMask
//    memory.rw.wdata <= rwDataIn
//    rwDataOut <= memory.rw.rdata

firrtl.circuit "MemoryRWSplit" {
  firrtl.module @MemoryRWSplit(%clock: !firrtl.clock, %rwEn: !firrtl.uint<1>, %rwMode: !firrtl.uint<1>, %rwAddr: !firrtl.uint<4>, %rwMask: !firrtl.uint<1>, %rwDataIn: !firrtl.uint<8>, %rwDataOut: !firrtl.flip<uint<8>>) {
    %memory_rw = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["rw"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>
    %0 = firrtl.subfield %memory_rw("clk") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>) -> !firrtl.clock
    firrtl.connect %0, %clock : !firrtl.clock, !firrtl.clock
    %1 = firrtl.subfield %memory_rw("en") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>) -> !firrtl.uint<1>
    firrtl.connect %1, %rwEn : !firrtl.uint<1>, !firrtl.uint<1>
    %2 = firrtl.subfield %memory_rw("addr") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>) -> !firrtl.uint<4>
    firrtl.connect %2, %rwAddr : !firrtl.uint<4>, !firrtl.uint<4>
    %3 = firrtl.subfield %memory_rw("wmode") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>) -> !firrtl.uint<1>
    firrtl.connect %3, %rwMode : !firrtl.uint<1>, !firrtl.uint<1>
    %4 = firrtl.subfield %memory_rw("wmask") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>) -> !firrtl.uint<1>
    firrtl.connect %4, %rwMask : !firrtl.uint<1>, !firrtl.uint<1>
    %5 = firrtl.subfield %memory_rw("wdata") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>) -> !firrtl.uint<8>
    firrtl.connect %5, %rwDataIn : !firrtl.uint<8>, !firrtl.uint<8>
    %6 = firrtl.subfield %memory_rw("rdata") : (!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>) -> !firrtl.uint<8>
    firrtl.connect %rwDataOut, %6 : !firrtl.flip<uint<8>>, !firrtl.uint<8>
  }

  // CHECK-LABEL: firrtl.module @MemoryRWSplit
  // COM: ---------------------------------------------------------------------------------
  // COM: The read write port, "rw", was split into "rw_r" and "rw_w"
  // CHECK: %memory_rw_r, %memory_rw_w = firrtl.mem
  // COM:   - port names are updated correctly
  // CHECK-SAME: portNames = ["rw_r", "rw_w"]
  // COM:   - the types are correct for read and write ports
  // CHECK-SAME: !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>, !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: uint<8>, mask: uint<1>>>
  // COM: ---------------------------------------------------------------------------------
  // COM: Read port is hooked up correctly
  // COM:   - address is "rw_addr"
  // CHECK: %memory_rw_addr = firrtl.wire
  // CHECK: %[[R_ADDR:.+]] = firrtl.subfield %memory_rw_r("addr")
  // CHECK: firrtl.connect %[[R_ADDR]], %memory_rw_addr
  // COM:   - enable is "rw_en && !rw_wmode"
  // CHECK: %memory_rw_en = firrtl.wire
  // CHECK: %memory_rw_wmode = firrtl.wire
  // CHECK: %[[NOT_WRITE:.+]] = firrtl.not %memory_rw_wmode
  // CHECK: %[[EN_AND_NOT_WRITE:.+]] = firrtl.and %memory_rw_en, %[[NOT_WRITE]]
  // CHECK: %[[R_EN:.+]] = firrtl.subfield %memory_rw_r("en")
  // CHECK: firrtl.connect %[[R_EN]], %[[EN_AND_NOT_WRITE]]
  // COM:   - clk is "rw_clk"
  // CHECK: %memory_rw_clk = firrtl.wire
  // CHECK: %[[R_CLK:.+]] = firrtl.subfield %memory_rw_r("clk")
  // CHECK: firrtl.connect %[[R_CLK]], %memory_rw_clk
  // COM:   - data has a reference
  // CHECK: %[[R_DATA:.+]] = firrtl.subfield %memory_rw_r("data")
  // COM: ---------------------------------------------------------------------------------
  // COM: Write port is hooked up correctly.
  // COM:   - address is "rw_addr"
  // CHECK: %[[W_ADDR:.+]] = firrtl.subfield %memory_rw_w("addr")
  // CHECK: firrtl.connect %[[W_ADDR]], %memory_rw_addr
  // COM:   - enable is "rw_en && rw_wmode"
  // CHECK: %[[EN_AND_WRITE:.+]] = firrtl.and %memory_rw_en, %memory_rw_wmode
  // CHECK: %[[W_EN:.+]] = firrtl.subfield %memory_rw_w("en")
  // CHECK: firrtl.connect %[[W_EN]], %[[EN_AND_WRITE]]
  // COM:   - clk is "rw_clk"
  // CHECK: %[[W_CLK:.+]] = firrtl.subfield %memory_rw_w("clk")
  // CHECK: firrtl.connect %[[W_CLK]], %memory_rw_clk
  // COM:   - data has a reference
  // CHECK: %[[W_DATA:.+]] = firrtl.subfield %memory_rw_w("data")
  // COM:   - mask has a reference
  // CHECK: %[[W_MASK:.+]] = firrtl.subfield %memory_rw_w("mask")
  // COM: ---------------------------------------------------------------------------------
  // COM: Check that the lowering is worked.
  // CHECK: firrtl.connect %memory_rw_clk, %clock
  // CHECK: firrtl.connect %memory_rw_en, %rwEn
  // CHECK: firrtl.connect %memory_rw_addr, %rwAddr
  // CHECK: firrtl.connect %memory_rw_wmode, %rwMode
  // CHECK: firrtl.connect %[[W_MASK]], %rwMask
  // CHECK: firrtl.connect %[[W_DATA]], %rwDataIn
  // CHECK: firrtl.connect %rwDataOut, %[[R_DATA]]
}

// -----

firrtl.circuit "MemoryRWSplitUnique" {
  firrtl.module @MemoryRWSplitUnique() {
    %memory_rw, %memory_rw_r, %memory_rw_w = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["rw", "rw_r", "rw_w"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>, !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>, !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: uint<8>, mask: uint<1>>>
  }

  // CHECK-LABEL: firrtl.module @MemoryRWSplitUnique
  // CHECK: %memory_rw_r, %memory_rw_w, %memory_rw_r0, %memory_rw_w0 = firrtl.mem
  // COM:   - port names are updated correctly
  // CHECK-SAME: portNames = ["rw_r", "rw_w", "rw_r0", "rw_w0"]

}

// -----
// https://github.com/llvm/circt/issues/593

module  {
  firrtl.circuit "top_mod" {
    firrtl.module @mod_2(%clock: !firrtl.clock, %inp_a: !firrtl.bundle<inp_d: uint<14>>) {
    }
    firrtl.module @top_mod(%clock: !firrtl.clock) {
      %U0_clock, %U0_inp_a = firrtl.instance @mod_2 {name = "U0"} : !firrtl.flip<clock>, !firrtl.flip<bundle<inp_d: uint<14>>>
      %0 = firrtl.invalidvalue : !firrtl.clock
      firrtl.connect %U0_clock, %0 : !firrtl.flip<clock>, !firrtl.clock
      %1 = firrtl.invalidvalue : !firrtl.bundle<inp_d: uint<14>>
      firrtl.connect %U0_inp_a, %1 : !firrtl.flip<bundle<inp_d: uint<14>>>, !firrtl.bundle<inp_d: uint<14>>
    }
  }
}

//CHECK-LABEL: module  {
//CHECK-NEXT:   firrtl.circuit "top_mod" {
//CHECK-NEXT:     firrtl.module @mod_2(%clock: !firrtl.clock, %inp_a_inp_d: !firrtl.uint<14>) {
//CHECK-NEXT:     }
//CHECK-NEXT:    firrtl.module @top_mod(%clock: !firrtl.clock) {
//CHECK-NEXT:      %U0_clock, %U0_inp_a_inp_d = firrtl.instance @mod_2 {name = "U0"} : !firrtl.flip<clock>, !firrtl.flip<uint<14>>
//CHECK-NEXT:      %0 = firrtl.invalidvalue : !firrtl.clock
//CHECK-NEXT:      firrtl.connect %U0_clock, %0 : !firrtl.flip<clock>, !firrtl.clock
//CHECK-NEXT:      %1 = firrtl.invalidvalue : !firrtl.uint<14>
//CHECK-NEXT:      firrtl.connect %U0_inp_a_inp_d, %1 : !firrtl.flip<uint<14>>, !firrtl.uint<14>
//CHECK-NEXT:    }
//CHECK-NEXT:  }
//CHECK-NEXT:}

// -----
// https://github.com/llvm/circt/issues/661

// COM: This test is just checking that the following doesn't error.
module  {
  firrtl.circuit "Issue661" {
    // CHECK-LABEL: firrtl.module @Issue661
    firrtl.module @Issue661(%clock: !firrtl.clock) {
      %head_MPORT_2, %head_MPORT_6 = firrtl.mem Undefined {depth = 20 : i64, name = "head", portNames = ["MPORT_2", "MPORT_6"], readLatency = 0 : i32, writeLatency = 1 : i32}
      : !firrtl.flip<bundle<addr: uint<5>, en: uint<1>, clk: clock, data: uint<5>, mask: uint<1>>>,
        !firrtl.flip<bundle<addr: uint<5>, en: uint<1>, clk: clock, data: uint<5>, mask: uint<1>>>
      %127 = firrtl.subfield %head_MPORT_6("clk") : (!firrtl.flip<bundle<addr: uint<5>, en: uint<1>, clk: clock, data: uint<5>, mask: uint<1>>>) -> !firrtl.clock
    }
  }
}

firrtl.circuit "RegBundle" {
    // CHECK-LABEL: firrtl.module @RegBundle(%a_a: !firrtl.uint<1>, %clk: !firrtl.clock, %b_a: !firrtl.flip<uint<1>>) {
    firrtl.module @RegBundle(%a: !firrtl.bundle<a: uint<1>>, %clk: !firrtl.clock, %b: !firrtl.flip<bundle<a: uint<1>>>) {
      // CHECK-NEXT: %x_a = firrtl.reg %clk : (!firrtl.clock) -> !firrtl.uint<1>
      // CHECK-NEXT: firrtl.connect %x_a, %a_a : !firrtl.uint<1>, !firrtl.uint<1>
      // CHECK-NEXT: firrtl.connect %b_a, %x_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      %x = firrtl.reg %clk {name = "x"} : (!firrtl.clock) -> !firrtl.bundle<a: uint<1>>
      %0 = firrtl.subfield %x("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
      %1 = firrtl.subfield %a("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
      firrtl.connect %0, %1 : !firrtl.uint<1>, !firrtl.uint<1>
      %2 = firrtl.subfield %b("a") : (!firrtl.flip<bundle<a: uint<1>>>) -> !firrtl.uint<1>
      %3 = firrtl.subfield %x("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
      firrtl.connect %2, %3 : !firrtl.uint<1>, !firrtl.uint<1>
    }
}

// -----

firrtl.circuit "RegBundleWithBulkConnect" {
    // CHECK-LABEL: firrtl.module @RegBundleWithBulkConnect(%a_a: !firrtl.uint<1>, %clk: !firrtl.clock, %b_a: !firrtl.flip<uint<1>>) {
    firrtl.module @RegBundleWithBulkConnect(%a: !firrtl.bundle<a: uint<1>>, %clk: !firrtl.clock, %b: !firrtl.flip<bundle<a: uint<1>>>) {
      // CHECK-NEXT: %x_a = firrtl.reg %clk : (!firrtl.clock) -> !firrtl.uint<1>
      // CHECK-NEXT: firrtl.connect %x_a, %a_a : !firrtl.uint<1>, !firrtl.uint<1>
      // CHECK-NEXT: firrtl.connect %b_a, %x_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      %x = firrtl.reg %clk {name = "x"} : (!firrtl.clock) -> !firrtl.bundle<a: uint<1>>
      firrtl.connect %x, %a : !firrtl.bundle<a: uint<1>>, !firrtl.bundle<a: uint<1>>
      firrtl.connect %b, %x : !firrtl.flip<bundle<a: uint<1>>>, !firrtl.bundle<a: uint<1>>
    }
}

// -----

firrtl.circuit "WireBundle" {
    // CHECK-LABEL: firrtl.module @WireBundle(%a_a: !firrtl.uint<1>,  %b_a: !firrtl.flip<uint<1>>) {
    firrtl.module @WireBundle(%a: !firrtl.bundle<a: uint<1>>,  %b: !firrtl.flip<bundle<a: uint<1>>>) {
      // CHECK-NEXT: %x_a = firrtl.wire  : !firrtl.uint<1>
      // CHECK-NEXT: firrtl.connect %x_a, %a_a : !firrtl.uint<1>, !firrtl.uint<1>
      // CHECK-NEXT: firrtl.connect %b_a, %x_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      %x = firrtl.wire : !firrtl.bundle<a: uint<1>>
      %0 = firrtl.subfield %x("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
      %1 = firrtl.subfield %a("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
      firrtl.connect %0, %1 : !firrtl.uint<1>, !firrtl.uint<1>
      %2 = firrtl.subfield %b("a") : (!firrtl.flip<bundle<a: uint<1>>>) -> !firrtl.uint<1>
      %3 = firrtl.subfield %x("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
      firrtl.connect %2, %3 : !firrtl.uint<1>, !firrtl.uint<1>
    }
}

// -----

firrtl.circuit "WireBundlesWithBulkConnect" {
  // CHECK-LABEL: firrtl.module @WireBundlesWithBulkConnect
  firrtl.module @WireBundlesWithBulkConnect(%source: !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>,
                             %sink: !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>) {
    // CHECK: %w_valid = firrtl.wire  : !firrtl.uint<1>
    // CHECK: %w_ready = firrtl.wire  : !firrtl.uint<1>
    // CHECK: %w_data = firrtl.wire  : !firrtl.uint<64>
    %w = firrtl.wire : !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>
    // CHECK: firrtl.connect %w_valid, %source_valid : !firrtl.uint<1>, !firrtl.uint<1>
    // CHECK: firrtl.connect %source_ready, %w_ready : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    // CHECK: firrtl.connect %w_data, %source_data : !firrtl.uint<64>, !firrtl.uint<64>
    firrtl.connect %w, %source : !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>, !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>
    // CHECK: firrtl.connect %sink_valid, %w_valid : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    // CHECK: firrtl.connect %w_ready, %sink_ready : !firrtl.uint<1>, !firrtl.uint<1>
    // CHECK: firrtl.connect %sink_data, %w_data : !firrtl.flip<uint<64>>, !firrtl.uint<64>
    firrtl.connect %sink, %w : !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>, !firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>
  }
}

// -----
// COM: Test vector lowering
firrtl.circuit "LowerVectors" {
  firrtl.module @LowerVectors(%a: !firrtl.vector<uint<1>, 2>, %b: !firrtl.flip<vector<uint<1>, 2>>) {
    firrtl.connect %b, %a: !firrtl.flip<vector<uint<1>, 2>>, !firrtl.vector<uint<1>, 2>
  }
  // CHECK-LABEL: firrtl.module @LowerVectors(%a_0: !firrtl.uint<1>, %a_1: !firrtl.uint<1>, %b_0: !firrtl.flip<uint<1>>, %b_1: !firrtl.flip<uint<1>>)
  // CHECK: firrtl.connect %b_0, %a_0
  // CHECK: firrtl.connect %b_1, %a_1
}

// -----

// COM: Test vector of bundles lowering
firrtl.circuit "LowerVectorsOfBundles" {
  // CHECK-LABEL: firrtl.module @LowerVectorsOfBundles(%in_0_a: !firrtl.uint<1>, %in_0_b: !firrtl.flip<uint<1>>, %in_1_a: !firrtl.uint<1>, %in_1_b: !firrtl.flip<uint<1>>, %out_0_a: !firrtl.flip<uint<1>>, %out_0_b: !firrtl.uint<1>, %out_1_a: !firrtl.flip<uint<1>>, %out_1_b: !firrtl.uint<1>) {
  firrtl.module @LowerVectorsOfBundles(%in: !firrtl.vector<bundle<a : uint<1>, b : flip<uint<1>>>, 2>,
                                       %out: !firrtl.flip<vector<bundle<a : uint<1>, b : flip<uint<1>>>, 2>>) {
    // CHECK: firrtl.connect %out_0_a, %in_0_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    // CHECK: firrtl.connect %in_0_b, %out_0_b : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    // CHECK: firrtl.connect %out_1_a, %in_1_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    // CHECK: firrtl.connect %in_1_b, %out_1_b : !firrtl.flip<uint<1>>, !firrtl.uint<1>
    firrtl.connect %out, %in: !firrtl.flip<vector<bundle<a : uint<1>, b : flip<uint<1>>>, 2>>, !firrtl.vector<bundle<a : uint<1>, b : flip<uint<1>>>, 2>
  }
}

// -----
firrtl.circuit "ExternalModule" {
  // CHECK-LABEL: firrtl.extmodule @ExternalModule(%source_valid: !firrtl.uint<1>, %source_ready: !firrtl.flip<uint<1>>, %source_data: !firrtl.uint<64>)
  firrtl.extmodule @ExternalModule(!firrtl.bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>> ) attributes {portNames = ["source"]}
  firrtl.module @Test() {
    // CHECK:  %inst_source_valid, %inst_source_ready, %inst_source_data = firrtl.instance @ExternalModule  {name = ""} : !firrtl.flip<uint<1>>, !firrtl.uint<1>, !firrtl.flip<uint<64>>
    %inst_source = firrtl.instance @ExternalModule {name = ""} : !firrtl.flip<bundle<valid: uint<1>, ready: flip<uint<1>>, data: uint<64>>>
  }
}

// -----

// Test RegResetOp lowering
firrtl.circuit "LowerRegResetOp" {
  // CHECK-LABEL: firrtl.module @LowerRegResetOp
  firrtl.module @LowerRegResetOp(%clock: !firrtl.clock, %reset: !firrtl.uint<1>, %a_d: !firrtl.vector<uint<1>, 2>, %a_q: !firrtl.flip<vector<uint<1>, 2>>) {
    %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
    %init = firrtl.wire  : !firrtl.vector<uint<1>, 2>
    %0 = firrtl.subindex %init[0] : !firrtl.vector<uint<1>, 2>
    firrtl.connect %0, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
    %1 = firrtl.subindex %init[1] : !firrtl.vector<uint<1>, 2>
    firrtl.connect %1, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
    %r = firrtl.regreset %clock, %reset, %init {name = "r"} : (!firrtl.clock, !firrtl.uint<1>, !firrtl.vector<uint<1>, 2>) -> !firrtl.vector<uint<1>, 2>
    firrtl.connect %r, %a_d : !firrtl.vector<uint<1>, 2>, !firrtl.vector<uint<1>, 2>
    firrtl.connect %a_q, %r : !firrtl.flip<vector<uint<1>, 2>>, !firrtl.vector<uint<1>, 2>
  }
  // CHECK:   %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
  // CHECK:   %init_0 = firrtl.wire  : !firrtl.uint<1>
  // CHECK:   %init_1 = firrtl.wire  : !firrtl.uint<1>
  // CHECK:   firrtl.connect %init_0, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
  // CHECK:   firrtl.connect %init_1, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
  // CHECK:   %r_0 = firrtl.regreset %clock, %reset, %init_0 : (!firrtl.clock, !firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
  // CHECK:   %r_1 = firrtl.regreset %clock, %reset, %init_1 : (!firrtl.clock, !firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
  // CHECK:   firrtl.connect %r_0, %a_d_0 : !firrtl.uint<1>, !firrtl.uint<1>
  // CHECK:   firrtl.connect %r_1, %a_d_1 : !firrtl.uint<1>, !firrtl.uint<1>
  // CHECK:   firrtl.connect %a_q_0, %r_0 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
  // CHECK:   firrtl.connect %a_q_1, %r_1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
}

// -----

// Test RegResetOp lowering without name attribute
// https://github.com/llvm/circt/issues/795
firrtl.circuit "LowerRegResetOpNoName" {
  // CHECK-LABEL: firrtl.module @LowerRegResetOpNoName
  firrtl.module @LowerRegResetOpNoName(%clock: !firrtl.clock, %reset: !firrtl.uint<1>, %a_d: !firrtl.vector<uint<1>, 2>, %a_q: !firrtl.flip<vector<uint<1>, 2>>) {
    %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
    %init = firrtl.wire  : !firrtl.vector<uint<1>, 2>
    %0 = firrtl.subindex %init[0] : !firrtl.vector<uint<1>, 2>
    firrtl.connect %0, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
    %1 = firrtl.subindex %init[1] : !firrtl.vector<uint<1>, 2>
    firrtl.connect %1, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
    %r = firrtl.regreset %clock, %reset, %init {name = ""} : (!firrtl.clock, !firrtl.uint<1>, !firrtl.vector<uint<1>, 2>) -> !firrtl.vector<uint<1>, 2>
    firrtl.connect %r, %a_d : !firrtl.vector<uint<1>, 2>, !firrtl.vector<uint<1>, 2>
    firrtl.connect %a_q, %r : !firrtl.flip<vector<uint<1>, 2>>, !firrtl.vector<uint<1>, 2>
  }
  // CHECK:   %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
  // CHECK:   %init_0 = firrtl.wire  : !firrtl.uint<1>
  // CHECK:   %init_1 = firrtl.wire  : !firrtl.uint<1>
  // CHECK:   firrtl.connect %init_0, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
  // CHECK:   firrtl.connect %init_1, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
  // CHECK:   %0 = firrtl.regreset %clock, %reset, %init_0 : (!firrtl.clock, !firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
  // CHECK:   %1 = firrtl.regreset %clock, %reset, %init_1 : (!firrtl.clock, !firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
  // CHECK:   firrtl.connect %0, %a_d_0 : !firrtl.uint<1>, !firrtl.uint<1>
  // CHECK:   firrtl.connect %1, %a_d_1 : !firrtl.uint<1>, !firrtl.uint<1>
  // CHECK:   firrtl.connect %a_q_0, %0 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
  // CHECK:   firrtl.connect %a_q_1, %1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
}

// -----

// Test RegOp lowering without name attribute
// https://github.com/llvm/circt/issues/795
firrtl.circuit "lowerRegOpNoName" {
  // CHECK-LABEL: firrtl.module @lowerRegOpNoName
  firrtl.module @lowerRegOpNoName(%clock: !firrtl.clock, %a_d: !firrtl.vector<uint<1>, 2>, %a_q: !firrtl.flip<vector<uint<1>, 2>>) {
    %r = firrtl.reg %clock {name = ""} : (!firrtl.clock) -> !firrtl.vector<uint<1>, 2>
      firrtl.connect %r, %a_d : !firrtl.vector<uint<1>, 2>, !firrtl.vector<uint<1>, 2>
      firrtl.connect %a_q, %r : !firrtl.flip<vector<uint<1>, 2>>, !firrtl.vector<uint<1>, 2>
  }
 // CHECK:    %0 = firrtl.reg %clock : (!firrtl.clock) -> !firrtl.uint<1>
 // CHECK:    %1 = firrtl.reg %clock : (!firrtl.clock) -> !firrtl.uint<1>
 // CHECK:    firrtl.connect %0, %a_d_0 : !firrtl.uint<1>, !firrtl.uint<1>
 // CHECK:    firrtl.connect %1, %a_d_1 : !firrtl.uint<1>, !firrtl.uint<1>
 // CHECK:    firrtl.connect %a_q_0, %0 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
 // CHECK:    firrtl.connect %a_q_1, %1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
}

// -----

// Test that InstanceOp Annotations are copied to the new instance.
// CHECK-LABEL: firrtl.circuit "AnnotationsInstanceOp"
firrtl.circuit "AnnotationsInstanceOp" {
  firrtl.module @Bar(%a: !firrtl.flip<vector<uint<1>, 2>>) {
    %0 = firrtl.invalidvalue : !firrtl.vector<uint<1>, 2>
    firrtl.connect %a, %0 : !firrtl.flip<vector<uint<1>, 2>>, !firrtl.vector<uint<1>, 2>
  }
  firrtl.module @AnnotationsInstanceOp() {
    %bar_a = firrtl.instance @Bar  {annotations = [{a = "a"}], name = "bar"} : !firrtl.vector<uint<1>, 2>
  }
  // CHECK: firrtl.instance
  // CHECK-SAME: annotations = [{a = "a"}]
}

// -----

// Test that MemOp Annotations are copied to lowered MemOps.
firrtl.circuit "AnnotationsMemOp" {
  // CHECK-LABEL: firrtl.module @AnnotationsMemOp
  firrtl.module @AnnotationsMemOp() {
    %bar_r, %bar_w = firrtl.mem Undefined  {annotations = [{a = "a"}], depth = 16 : i64, name = "bar", portNames = ["r", "w"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<vector<uint<8>, 2>>>>, !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: vector<uint<8>, 2>, mask: vector<uint<1>, 2>>>
  }
  // CHECK: firrtl.mem
  // CHECK-SAME: annotations = [{a = "a"}]
  // CHECK: firrtl.mem
  // CHECK-SAME: annotations = [{a = "a"}]
}

// -----

// Test that WireOp Annotations are copied to lowered WireOps.
firrtl.circuit "AnnotationsWireOp" {
  // CHECK-LABEL: firrtl.module @AnnotationsWireOp
  firrtl.module @AnnotationsWireOp() {
    %bar = firrtl.wire  {annotations = [{a = "a"}]} : !firrtl.vector<uint<1>, 2>
  }
  // CHECK: firrtl.wire
  // CHECK-SAME: annotations = [{a = "a"}]
  // CHECK: firrtl.wire
  // CHECK-SAME: annotations = [{a = "a"}]
}

// -----

// Test that Reg/RegResetOp Annotations are copied to lowered registers.
firrtl.circuit "AnnotationsRegOp" {
  // CHECK-LABEL: firrtl.module @AnnotationsRegOp
  firrtl.module @AnnotationsRegOp(%clock: !firrtl.clock, %reset: !firrtl.uint<1>) {
    %bazInit = firrtl.wire  : !firrtl.vector<uint<1>, 2>
    %0 = firrtl.subindex %bazInit[0] : !firrtl.vector<uint<1>, 2>
    %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
    firrtl.connect %0, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
    %1 = firrtl.subindex %bazInit[1] : !firrtl.vector<uint<1>, 2>
    firrtl.connect %1, %c0_ui1 : !firrtl.uint<1>, !firrtl.uint<1>
    %bar = firrtl.reg %clock  {annotations = [{a = "a"}], name = "bar"} : (!firrtl.clock) -> !firrtl.vector<uint<1>, 2>
    %baz = firrtl.regreset %clock, %reset, %bazInit  {annotations = [{b = "b"}], name = "baz"} : (!firrtl.clock, !firrtl.uint<1>, !firrtl.vector<uint<1>, 2>) -> !firrtl.vector<uint<1>, 2>
  }
  // CHECK: firrtl.reg
  // CHECK-SAME: annotations = [{a = "a"}]
  // CHECK: firrtl.reg
  // CHECK-SAME: annotations = [{a = "a"}]
  // CHECK: firrtl.regreset
  // CHECK-SAME: annotations = [{b = "b"}]
  // CHECK: firrtl.regreset
  // CHECK-SAME: annotations = [{b = "b"}]
}

// -----

// Test that WhenOp with regions has its regions lowered.
firrtl.circuit "WhenOp" {
  firrtl.module @WhenOp (%p: !firrtl.uint<1>,
                         %in : !firrtl.bundle<a: uint<1>, b: uint<1>>,
                         %out : !firrtl.flip<bundle<a: uint<1>, b: uint<1>>>) {
    // No else region.
    firrtl.when %p {
      // CHECK: firrtl.connect %out_a, %in_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      // CHECK: firrtl.connect %out_b, %in_b : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      firrtl.connect %out, %in : !firrtl.flip<bundle<a: uint<1>, b: uint<1>>>, !firrtl.bundle<a: uint<1>, b: uint<1>>
    }

    // Else region.
    firrtl.when %p {
      // CHECK: firrtl.connect %out_a, %in_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      // CHECK: firrtl.connect %out_b, %in_b : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      firrtl.connect %out, %in : !firrtl.flip<bundle<a: uint<1>, b: uint<1>>>, !firrtl.bundle<a: uint<1>, b: uint<1>>
    } else {
      // CHECK: firrtl.connect %out_a, %in_a : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      // CHECK: firrtl.connect %out_b, %in_b : !firrtl.flip<uint<1>>, !firrtl.uint<1>
      firrtl.connect %out, %in : !firrtl.flip<bundle<a: uint<1>, b: uint<1>>>, !firrtl.bundle<a: uint<1>, b: uint<1>>
    }
  }
}

// -----

// Test wire connection semantics.  Based on the flippedness of the destination
// type, the connection may be reversed.
firrtl.circuit "WireSemantics"  {
  firrtl.module @WireSemantics() {
    %a = firrtl.wire  : !firrtl.bundle<a: bundle<a: uint<1>>>
    %ax = firrtl.wire  : !firrtl.bundle<a: bundle<a: uint<1>>>
    firrtl.connect %a, %ax : !firrtl.bundle<a: bundle<a: uint<1>>>, !firrtl.bundle<a: bundle<a: uint<1>>>
    // COM: a <= ax
    // CHECK: firrtl.connect %a_a_a, %ax_a_a
    %0 = firrtl.subfield %a("a") : (!firrtl.bundle<a: bundle<a: uint<1>>>) -> !firrtl.bundle<a: uint<1>>
    %1 = firrtl.subfield %ax("a") : (!firrtl.bundle<a: bundle<a: uint<1>>>) -> !firrtl.bundle<a: uint<1>>
    firrtl.connect %0, %1 : !firrtl.bundle<a: uint<1>>, !firrtl.bundle<a: uint<1>>
    // COM: a.a <= ax.a
    // CHECK: firrtl.connect %a_a_a, %ax_a_a
    %2 = firrtl.subfield %a("a") : (!firrtl.bundle<a: bundle<a: uint<1>>>) -> !firrtl.bundle<a: uint<1>>
    %3 = firrtl.subfield %2("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
    %4 = firrtl.subfield %ax("a") : (!firrtl.bundle<a: bundle<a: uint<1>>>) -> !firrtl.bundle<a: uint<1>>
    %5 = firrtl.subfield %4("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
    firrtl.connect %3, %5 : !firrtl.uint<1>, !firrtl.uint<1>
    // COM: a.a.a <= ax.a.a
    // CHECK: firrtl.connect %a_a_a, %ax_a_a
    %b = firrtl.wire  : !firrtl.bundle<a: bundle<a: flip<uint<1>>>>
    %bx = firrtl.wire  : !firrtl.bundle<a: bundle<a: flip<uint<1>>>>
    firrtl.connect %b, %bx : !firrtl.bundle<a: bundle<a: flip<uint<1>>>>, !firrtl.bundle<a: bundle<a: flip<uint<1>>>>
    // COM: b <= bx
    // CHECK: firrtl.connect %bx_a_a, %b_a_a
    %6 = firrtl.subfield %b("a") : (!firrtl.bundle<a: bundle<a: flip<uint<1>>>>) -> !firrtl.bundle<a: flip<uint<1>>>
    %7 = firrtl.subfield %bx("a") : (!firrtl.bundle<a: bundle<a: flip<uint<1>>>>) -> !firrtl.bundle<a: flip<uint<1>>>
    firrtl.connect %6, %7 : !firrtl.bundle<a: flip<uint<1>>>, !firrtl.bundle<a: flip<uint<1>>>
    // COM: b.a <= bx.a
    // CHECK: firrtl.connect %bx_a_a, %b_a_a
    %8 = firrtl.subfield %b("a") : (!firrtl.bundle<a: bundle<a: flip<uint<1>>>>) -> !firrtl.bundle<a: flip<uint<1>>>
    %9 = firrtl.subfield %8("a") : (!firrtl.bundle<a: flip<uint<1>>>) -> !firrtl.uint<1>
    %10 = firrtl.subfield %bx("a") : (!firrtl.bundle<a: bundle<a: flip<uint<1>>>>) -> !firrtl.bundle<a: flip<uint<1>>>
    %11 = firrtl.subfield %10("a") : (!firrtl.bundle<a: flip<uint<1>>>) -> !firrtl.uint<1>
    firrtl.connect %9, %11 : !firrtl.uint<1>, !firrtl.uint<1>
    // COM: b.a.a <= bx.a.a
    // CHECK: firrtl.connect %b_a_a, %bx_a_a
    %c = firrtl.wire  : !firrtl.bundle<a: flip<bundle<a: uint<1>>>>
    %cx = firrtl.wire  : !firrtl.bundle<a: flip<bundle<a: uint<1>>>>
    firrtl.connect %c, %cx : !firrtl.bundle<a: flip<bundle<a: uint<1>>>>, !firrtl.bundle<a: flip<bundle<a: uint<1>>>>
    // COM: c <= cx
    // CHECK: firrtl.connect %cx_a_a, %c_a_a
    %12 = firrtl.subfield %c("a") : (!firrtl.bundle<a: flip<bundle<a: uint<1>>>>) -> !firrtl.bundle<a: uint<1>>
    %13 = firrtl.subfield %cx("a") : (!firrtl.bundle<a: flip<bundle<a: uint<1>>>>) -> !firrtl.bundle<a: uint<1>>
    firrtl.connect %12, %13 : !firrtl.bundle<a: uint<1>>, !firrtl.bundle<a: uint<1>>
    // COM: c.a <= cx.a
    // CHECK: firrtl.connect %c_a_a, %cx_a_a
    %14 = firrtl.subfield %c("a") : (!firrtl.bundle<a: flip<bundle<a: uint<1>>>>) -> !firrtl.bundle<a: uint<1>>
    %15 = firrtl.subfield %14("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
    %16 = firrtl.subfield %cx("a") : (!firrtl.bundle<a: flip<bundle<a: uint<1>>>>) -> !firrtl.bundle<a: uint<1>>
    %17 = firrtl.subfield %16("a") : (!firrtl.bundle<a: uint<1>>) -> !firrtl.uint<1>
    firrtl.connect %15, %17 : !firrtl.uint<1>, !firrtl.uint<1>
    // COM: c.a.a <= cx.a.a
    // CHECK: firrtl.connect %c_a_a, %cx_a_a
    %d = firrtl.wire  : !firrtl.bundle<a: flip<bundle<a: flip<uint<1>>>>>
    %dx = firrtl.wire  : !firrtl.bundle<a: flip<bundle<a: flip<uint<1>>>>>
    firrtl.connect %d, %dx : !firrtl.bundle<a: flip<bundle<a: flip<uint<1>>>>>, !firrtl.bundle<a: flip<bundle<a: flip<uint<1>>>>>
    // COM: d <= dx
    // CHECK: firrtl.connect %d_a_a, %dx_a_a
    %18 = firrtl.subfield %d("a") : (!firrtl.bundle<a: flip<bundle<a: flip<uint<1>>>>>) -> !firrtl.bundle<a: flip<uint<1>>>
    %19 = firrtl.subfield %dx("a") : (!firrtl.bundle<a: flip<bundle<a: flip<uint<1>>>>>) -> !firrtl.bundle<a: flip<uint<1>>>
    firrtl.connect %18, %19 : !firrtl.bundle<a: flip<uint<1>>>, !firrtl.bundle<a: flip<uint<1>>>
    // COM: d.a <= dx.a
    // CHECK: firrtl.connect %dx_a_a, %d_a_a
    %20 = firrtl.subfield %d("a") : (!firrtl.bundle<a: flip<bundle<a: flip<uint<1>>>>>) -> !firrtl.bundle<a: flip<uint<1>>>
    %21 = firrtl.subfield %20("a") : (!firrtl.bundle<a: flip<uint<1>>>) -> !firrtl.uint<1>
    %22 = firrtl.subfield %dx("a") : (!firrtl.bundle<a: flip<bundle<a: flip<uint<1>>>>>) -> !firrtl.bundle<a: flip<uint<1>>>
    %23 = firrtl.subfield %22("a") : (!firrtl.bundle<a: flip<uint<1>>>) -> !firrtl.uint<1>
    firrtl.connect %21, %23 : !firrtl.uint<1>, !firrtl.uint<1>
    // COM: d.a.a <= dx.a.a
    // CHECK: firrtl.connect %d_a_a, %dx_a_a
  }
}
