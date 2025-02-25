// RUN: circt-translate -export-verilog -verify-diagnostics --split-input-file -mlir-print-op-on-diagnostic=false %s

// expected-error @+1 {{value has an unsupported verilog type 'f32'}}
rtl.module @Top(%out: f32) {
}

// expected-error @+1 {{'rtl.module' op name "parameter" is not allowed in Verilog output}}
rtl.module @parameter() {
}

// -----

// expected-error @+2 {{unknown style option 'badOption'}}
// expected-error @+1 {{unknown style option 'anotherOne'}}
module attributes {circt.loweringOptions = "badOption,anotherOne"} {}