// RUN: circt-opt %s -split-input-file -verify-diagnostics

firrtl.circuit "X" {

firrtl.module @X(%b : !firrtl.unknowntype) {
  // expected-error @-1 {{unknown firrtl type}}
}

}

// -----

firrtl.circuit "X" {

firrtl.module @X(%b : !firrtl.uint<32>, %d : !firrtl.uint<16>, %out : !firrtl.uint) {
  // expected-error @+1 {{'firrtl.add' op expected 2 operands, but found 3}}
  %3 = "firrtl.add"(%b, %d, %out) : (!firrtl.uint<32>, !firrtl.uint<16>, !firrtl.uint) -> !firrtl.uint<32>
}

}

// -----

// expected-error @+1 {{'firrtl.circuit' op must contain one module that matches main name 'MyCircuit'}}
firrtl.circuit "MyCircuit" {

"firrtl.module"() ( {
}) { type = () -> ()} : () -> ()

}

// -----


// expected-error @+1 {{'firrtl.module' op expects parent op 'firrtl.circuit'}}
firrtl.module @X() {}

// -----

// expected-error @+1 {{'firrtl.circuit' op must contain one module that matches main name 'Foo'}}
firrtl.circuit "Foo" {

firrtl.module @Bar() {}

}

// -----

// expected-error @+1 {{'firrtl.circuit' op must have a non-empty name}}
firrtl.circuit "" {
}

// -----

firrtl.circuit "Foo" {
  firrtl.module @Foo(%clk: !firrtl.uint<1>, %reset: !firrtl.uint<1>) {
    // expected-error @+1 {{'firrtl.reg' op operand #0 must be clock, but got '!firrtl.uint<1>'}}
    %a = firrtl.reg %clk {name = "a"} : (!firrtl.uint<1>) -> !firrtl.uint<1>
  }
}

// -----

firrtl.circuit "Foo" {
  firrtl.module @Foo(%clk: !firrtl.uint<1>, %reset: !firrtl.uint<1>) {
    %zero = firrtl.constant(0 : ui1) : !firrtl.uint<1>
    // expected-error @+1 {{'firrtl.regreset' op operand #0 must be clock, but got '!firrtl.uint<1>'}}
    %a = firrtl.regreset %clk, %reset, %zero {name = "a"} : (!firrtl.uint<1>, !firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
  }
}

// -----

firrtl.circuit "Foo" {
  firrtl.module @Foo(%clk: !firrtl.clock, %reset: !firrtl.uint<2>) {
    %zero = firrtl.constant(0 : ui1) : !firrtl.uint<1>
    // expected-error @+1 {{'firrtl.regreset' op operand #1 must be Reset, but got '!firrtl.uint<2>'}}
    %a = firrtl.regreset %clk, %reset, %zero {name = "a"} : (!firrtl.clock, !firrtl.uint<2>, !firrtl.uint<1>) -> !firrtl.uint<1>
  }
}

// -----

firrtl.circuit "Foo" {
  firrtl.module @Foo() {
  // expected-error @+1 {{'firrtl.mem' op attribute 'writeLatency' failed to satisfy constraint: 32-bit signless integer attribute whose minimum value is 1}}
    %m = firrtl.mem Undefined {depth = 32 : i64, name = "m", readLatency = 0 : i32, writeLatency = 0 : i32} : !firrtl.bundle<>
  }
}


// -----

firrtl.circuit "Foo" {
  firrtl.module @Foo(%clk: !firrtl.clock) {
    // expected-error @+1 {{'firrtl.reg' op result #0 must be a passive type (contain no flips)}}
    %a = firrtl.reg %clk {name = "a"} : (!firrtl.clock) -> !firrtl.flip<uint<1>>
  }
}

// -----

firrtl.circuit "Foo" {
  firrtl.module @Foo(%clk: !firrtl.clock, %reset: !firrtl.uint<1>) {
    %zero = firrtl.constant(0 : ui1) : !firrtl.uint<1>
    // expected-error @+1 {{'firrtl.regreset' op result #0 must be a passive type (contain no flips)}}
    %a = firrtl.regreset %clk, %reset, %zero {name = "a"} : (!firrtl.clock, !firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.flip<uint<1>>
  }
}

// -----

firrtl.circuit "Foo" {

  // expected-error @+1 {{'firrtl.extmodule' op attribute 'defname' with value "Bar" conflicts with the name of another module in the circuit}}
  firrtl.extmodule @Foo() attributes { defname = "Bar" }
  // expected-note @+1 {{previous module declared here}}
  firrtl.module @Bar() {}
  // Allow an extmodule to conflict with its own symbol name
  firrtl.extmodule @Baz() attributes { defname = "Baz" }

}

// -----

firrtl.circuit "Foo" {

  // expected-note @+1 {{previous extmodule definition occurred here}}
  firrtl.extmodule @Foo(%a : !firrtl.uint<1>) attributes { defname = "Foo" }
  // expected-error @+1 {{'firrtl.extmodule' op with 'defname' attribute "Foo" has 0 ports which is different from a previously defined extmodule with the same 'defname' which has 1 ports}}
  firrtl.extmodule @Bar() attributes { defname = "Foo" }

}

// -----

firrtl.circuit "Foo" {

  // expected-note @+1 {{previous extmodule definition occurred here}}
  firrtl.extmodule @Foo(%a : !firrtl.uint<1>) attributes { defname = "Foo" }
  // expected-error @+1 {{'firrtl.extmodule' op with 'defname' attribute "Foo" has a port with name "b" which does not match the name of the port in the same position of a previously defined extmodule with the same 'defname', expected port to have name "a"}}
  firrtl.extmodule @Foo_(%b : !firrtl.uint<1>) attributes { defname = "Foo" }

}

// -----

firrtl.circuit "Foo" {

  firrtl.extmodule @Foo(%a : !firrtl.uint<2>) attributes { defname = "Foo", parameters = { width = 2 : i32 } }
  // expected-note @+1 {{previous extmodule definition occurred here}}
  firrtl.extmodule @Bar(%a : !firrtl.uint<1>) attributes { defname = "Foo" }
  // expected-error @+1 {{'firrtl.extmodule' op with 'defname' attribute "Foo" has a port with name "a" which has a different type '!firrtl.uint<2>' which does not match the type of the port in the same position of a previously defined extmodule with the same 'defname', expected port to have type '!firrtl.uint<1>'}}
  firrtl.extmodule @Baz(%a : !firrtl.uint<2>) attributes { defname = "Foo" }

}

// -----

firrtl.circuit "Foo" {

  // expected-note @+1 {{previous extmodule definition occurred here}}
  firrtl.extmodule @Foo(%a : !firrtl.uint<1>) attributes { defname = "Foo" }
  // expected-error @+1 {{'firrtl.extmodule' op with 'defname' attribute "Foo" has a port with name "a" which has a different type '!firrtl.sint<1>' which does not match the type of the port in the same position of a previously defined extmodule with the same 'defname', expected port to have type '!firrtl.uint<1>'}}
  firrtl.extmodule @Foo_(%a : !firrtl.sint<1>) attributes { defname = "Foo" }

}

// -----

firrtl.circuit "Foo" {

  // expected-note @+1 {{previous extmodule definition occurred here}}
  firrtl.extmodule @Foo(%a : !firrtl.uint<2>) attributes { defname = "Foo", parameters = { width = 2 : i32 } }
  // expected-error @+1 {{'firrtl.extmodule' op with 'defname' attribute "Foo" has a port with name "a" which has a different type '!firrtl.sint' which does not match the type of the port in the same position of a previously defined extmodule with the same 'defname', expected port to have type '!firrtl.uint'}}
  firrtl.extmodule @Bar(%a : !firrtl.sint<1>) attributes { defname = "Foo" }

}

// -----

firrtl.circuit "Foo" {

  // expected-error @+1 {{has unknown extmodule parameter value 'width' = @Foo}}
  firrtl.extmodule @Foo(%a : !firrtl.uint<2>) attributes { defname = "Foo", parameters = { width = @Foo } }

}

// -----

firrtl.circuit "Foo" {

  firrtl.extmodule @Foo()
  // expected-error @+1 {{'firrtl.instance' op should be embedded in a 'firrtl.module'}}
  firrtl.instance @Foo {name = ""}

}

// -----

firrtl.circuit "Foo" {

  // expected-note @+1 {{containing module declared here}}
  firrtl.module @Foo() {
    // expected-error @+1 {{'firrtl.instance' op is a recursive instantiation of its containing module}}
    firrtl.instance @Foo {name = ""}
  }

}

// -----

firrtl.circuit "Foo" {

  // expected-note @+1 {{original module declared here}}
  firrtl.module @Callee(%arg0: !firrtl.uint<1>) { }
  firrtl.module @Foo() {
    // expected-error @+1 {{'firrtl.instance' op result type for "arg0" must be '!firrtl.flip<uint<1>>', but got '!firrtl.uint<2>'}}
    %a = firrtl.instance @Callee {name = ""} : !firrtl.uint<2>
  }
}

// -----

firrtl.circuit "Foo" {

  // expected-note @+1 {{original module declared here}}
  firrtl.module @Callee(%arg0: !firrtl.uint<1> ) { }
  firrtl.module @Foo() {
    // expected-error @+1 {{'firrtl.instance' op has a wrong number of results; expected 1 but got 0}}
    firrtl.instance @Callee {name = ""}
  }
}

// -----

firrtl.circuit "Foo" {

  // expected-note @+1 {{original module declared here}}
  firrtl.module @Callee(%arg0: !firrtl.uint<1>, %arg1: !firrtl.bundle<valid: uint<1>>) { }
  firrtl.module @Foo() {
    // expected-error @+1 {{'firrtl.instance' op result type for "arg0" must be '!firrtl.flip<uint<1>>', but got '!firrtl.uint<1>'}}
    %a:2 = firrtl.instance @Callee {name = ""}
    : !firrtl.uint<1>, !firrtl.bundle<valid: uint<2>>
  }
}

// -----

firrtl.circuit "X" {

firrtl.module @X(%a : !firrtl.uint<4>) {
  // expected-error @+1 {{high must be equal or greater than low, but got high = 3, low = 4}}
  %0 = firrtl.bits %a 3 to 4 : (!firrtl.uint<4>) -> !firrtl.uint<2>
}

}

// -----

firrtl.circuit "X" {

firrtl.module @X(%a : !firrtl.uint<4>) {
  // expected-error @+1 {{high must be smaller than the width of input, but got high = 4, width = 4}}
  %0 = firrtl.bits %a 4 to 3 : (!firrtl.uint<4>) -> !firrtl.uint<2>
}

}

// -----

firrtl.circuit "X" {

firrtl.module @X(%a : !firrtl.uint<4>) {
  // expected-error @+1 {{'firrtl.bits' op result type should be '!firrtl.uint<3>'}}
  %0 = firrtl.bits %a 3 to 1 : (!firrtl.uint<4>) -> !firrtl.uint<2>
}

}

// -----

firrtl.circuit "BadPort" {
  // expected-error @+1 {{'firrtl.module' op all module ports must be firrtl types}}
  firrtl.module @BadPort(%in1 : i1) {
  }
}

// -----

firrtl.circuit "BadPort" {
  firrtl.module @BadPort(%a : !firrtl.uint<1>) {
    // expected-error @+1 {{'firrtl.attach' op operand #0 must be analog type, but got '!firrtl.uint<1>'}}
    firrtl.attach %a, %a : !firrtl.uint<1>, !firrtl.uint<1>
  }
}

// -----

firrtl.circuit "BadAdd" {
  firrtl.module @BadAdd(%a : !firrtl.uint<1>) {
    // expected-error @+1 {{'firrtl.add' op result type should be '!firrtl.uint<2>'}}
    firrtl.add %a, %a : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
  }
}

// -----

firrtl.circuit "NodeMustBePassive" {
  firrtl.module @NodeMustBePassive(%a: !firrtl.flip<uint<1>>) {
    // expected-error @+1 {{'firrtl.node' op operand #0 must be a passive type}}
    %b = firrtl.node %a  : !firrtl.flip<uint<1>>
  }
}

// -----

firrtl.circuit "StructCast" {
  firrtl.module @StructCast() {
    %a = firrtl.wire : !firrtl.bundle<valid: uint<1>, ready: uint<1>, data: uint<64>>
    // expected-error @+1 {{bundle and struct have different number of fields}}
    %b = firrtl.rtlStructCast %a : (!firrtl.bundle<valid: uint<1>, ready: uint<1>, data: uint<64>>) -> (!rtl.struct<valid: i1, ready: i1>)
  }
}

// -----

firrtl.circuit "StructCast2" {
  firrtl.module @StructCast2() {
    %a = firrtl.wire : !firrtl.bundle<valid: uint<1>>
    // expected-error @+1 {{field names don't match 'valid', 'yovalid'}}
    %b = firrtl.rtlStructCast %a : (!firrtl.bundle<valid: uint<1>>) -> (!rtl.struct<yovalid: i1>)
  }
}

// -----

firrtl.circuit "StructCast3" {
  firrtl.module @StructCast3() {
    %a = firrtl.wire : !firrtl.bundle<valid: uint<1>>
    // expected-error @+1 {{size of field 'valid' don't match 1, 2}}
    %b = firrtl.rtlStructCast %a : (!firrtl.bundle<valid: uint<1>>) -> (!rtl.struct<valid: i2>)
  }
}

// -----

firrtl.circuit "OutOfOrder" {
  firrtl.module @OutOfOrder(%a: !firrtl.uint<32>) {
    // expected-error @+1 {{operand #0 does not dominate this use}}
    %0 = firrtl.add %1, %1 : (!firrtl.uint<33>, !firrtl.uint<33>) -> !firrtl.uint<34>
    // expected-note @+1 {{operand defined here}}
    %1 = firrtl.add %a, %a : (!firrtl.uint<32>, !firrtl.uint<32>) -> !firrtl.uint<33>
  }
}

// -----

firrtl.circuit "MemoryNegativeReadLatency" {
  firrtl.module @MemoryNegativeReadLatency() {
    // expected-error @+1 {{'firrtl.mem' op attribute 'readLatency' failed to satisfy constraint}}
    %memory_r = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r", "rw", "w"], readLatency = -1 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>
  }
}

// -----

firrtl.circuit "MemoryZeroWriteLatency" {
  firrtl.module @MemoryZeroWriteLatency() {
    // expected-error @+1 {{'firrtl.mem' op attribute 'writeLatency' failed to satisfy constraint}}
    %memory_r = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r", "rw", "w"], readLatency = 0 : i32, writeLatency = 0 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>
  }
}

// -----

firrtl.circuit "MemoryZeroDepth" {
  firrtl.module @MemoryZeroDepth() {
    // expected-error @+1 {{'firrtl.mem' op attribute 'depth' failed to satisfy constraint}}
    %memory_r = firrtl.mem Undefined {depth = 0 : i64, name = "memory", portNames = ["r", "rw", "w"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>
  }
}

// -----

firrtl.circuit "MemoryBadPortType" {
  firrtl.module @MemoryBadPortType() {
    // expected-error @+1 {{'firrtl.mem' op has an invalid type on port "r" (expected either '!firrtl.bundle<...>' or '!firrtl.flip<bundle<...>>'}}
    %memory_r = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.uint<1>
  }
}

// -----

firrtl.circuit "MemoryPortNamesCollide" {
  firrtl.module @MemoryPortNamesCollide() {
    // expected-error @+1 {{'firrtl.mem' op has non-unique port name "r"}}
    %memory_r, %memory_r_0 = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r", "r"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>, !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>
  }
}

// -----

firrtl.circuit "MemoryUnexpectedNumberOfFields" {
  firrtl.module @MemoryUnexpectedNumberOfFields() {
    // expected-error @+1 {{'firrtl.mem' op has an invalid number of fields on port "r" (expected 4 for read, 5 for write, or 7 for read/write)}}
    %memory_r = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.bundle<a: uint<1>>
  }
}

// -----

firrtl.circuit "MemoryMissingDataField" {
  firrtl.module @MemoryMissingDataField() {
    // expected-error @+1 {{'firrtl.mem' op has no data field on port "r" (expected to see "data" for a read or write port or "rdata" for a read/write port)}}
    %memory_r = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, rdata: flip<uint<8>>>>
  }
}

// -----

firrtl.circuit "MemoryMissingDataField2" {
  firrtl.module @MemoryMissingDataField2() {
    // expected-error @+1 {{'firrtl.mem' op has no data field on port "rw" (expected to see "data" for a read or write port or "rdata" for a read/write port)}}
    %memory_rw = firrtl.mem Undefined {depth = 16 : i64, name = "memory2", portNames = ["rw"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, writedata: uint<8>, wmask: uint<1>>>
  }
}

// -----

firrtl.circuit "MemoryDataNotPassive" {
  firrtl.module @MemoryDataNotPassive() {
    // expected-error @+1 {{'firrtl.mem' op has non-passive data type on port "r" (memory types must be passive)}}
    %memory_r = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<bundle<a: flip<uint<8>>, b: uint<8>>>>>
  }
}

// -----

firrtl.circuit "MemoryDataContainsAnalog" {
  firrtl.module @MemoryDataContainsAnalog() {
    // expected-error @+1 {{'firrtl.mem' op has a data type that contains an analog type on port "r" (memory types cannot contain analog types)}}
    %memory_r = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<bundle<a: uint<8>, b: analog<8>>>>>
  }
}

// -----

firrtl.circuit "MemoryPortInvalidReadKind" {
  firrtl.module @MemoryPortInvalidReadKind() {
    // expected-error @+1 {{'firrtl.mem' op has an invalid type for port "r" of determined kind "read" (expected '!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>', but got '!firrtl.flip<bundle<BAD: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>')}}
    %memory_r= firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<BAD: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>
  }
}

// -----

firrtl.circuit "MemoryPortInvalidWriteKind" {
  firrtl.module @MemoryPortInvalidWriteKind() {
    // expected-error @+1 {{'firrtl.mem' op has an invalid type for port "w" of determined kind "write" (expected '!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: uint<8>, mask: uint<1>>>', but got '!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: uint<8>, BAD: uint<1>>>')}}
    %memory_r= firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["w"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: uint<8>, BAD: uint<1>>>
  }
}

// -----

firrtl.circuit "MemoryPortInvalidReadWriteKind" {
  firrtl.module @MemoryPortInvalidReadWriteKind() {
    // expected-error @+1 {{'firrtl.mem' op has an invalid type for port "rw" of determined kind "readwrite" (expected '!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, wmask: uint<1>>>', but got '!firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, BAD: uint<1>>>')}}
    %memory_r= firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["rw"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, wmode: uint<1>, rdata: flip<uint<8>>, wdata: uint<8>, BAD: uint<1>>>
  }
}

// -----

firrtl.circuit "MemoryPortsWithDifferentTypes" {
  firrtl.module @MemoryPortsWithDifferentTypes() {
    // expected-error @+1 {{'firrtl.mem' op port "r1" has a different type than port "r0" (expected '!firrtl.uint<8>', but got '!firrtl.sint<8>')}}
    %memory_r0, %memory_r1 = firrtl.mem Undefined {depth = 16 : i64, name = "memory", portNames = ["r0", "r1"], readLatency = 0 : i32, writeLatency = 1 : i32} : !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<uint<8>>>>, !firrtl.flip<bundle<addr: uint<4>, en: uint<1>, clk: clock, data: flip<sint<8>>>>
  }
}
