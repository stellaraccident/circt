//===- SVInOutOps.td - SV ops pertaining to inout type -----*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This describes the SystemVerilog dialect ops for working with inout types.
// These are wires, connect statements, etc.
//
//===----------------------------------------------------------------------===//

def ConnectOp : SVOp<"connect", [InOutTypeConstraint<"src", "dest">]> {
  let summary = "Connect two signals";
  let description = [{
    Connect Operation:
    ```
      sv.connect %dest, %src : t1
    ```
    }];

  let arguments = (ins InOutType:$dest, RTLValueType:$src);
  let results = (outs);
  let assemblyFormat = "$dest `,` $src  attr-dict `:` type($src)";
}

// Note that net declarations like 'wire' should not appear in an always block.
def WireOp : SVOp<"wire", [DeclareOpInterfaceMethods<OpAsmOpInterface>,
                           NonProceduralOp]> {
  let summary = "Define a new wire";
  let description = [{
    Declare a SystemVerilog Net Declaration of 'wire' type.
     See SV Spec 6.7, pp97.
    }];

  let arguments = (ins StrAttr:$name);
  let results = (outs InOutType:$result);

  let skipDefaultBuilders = 1;
  let builders = [
    OpBuilder<(ins "::mlir::Type":$elementType,
                      CArg<"StringAttr", "StringAttr()">:$name)>,
    OpBuilder<(ins "::mlir::Type":$elementType, CArg<"StringRef">:$name), [{
      return build($_builder, $_state, elementType,
                   $_builder.getStringAttr(name));
    }]>
  ];

  let assemblyFormat = "custom<ImplicitSSAName>(attr-dict) `:` type($result)";
  let hasCanonicalizeMethod = true;

  let extraClassDeclaration = [{
    Type getElementType() {
      return result().getType().cast<InOutType>().getElementType();
    }
  }];
  let verifier = [{ return ::verifyWireOp(*this); }];
}

def RegOp : SVOp<"reg", [DeclareOpInterfaceMethods<OpAsmOpInterface>]> {
  let summary = "Define a new `reg` in SystemVerilog";
   let description = [{
     Declare a SystemVerilog Variable Declaration of 'reg' type.
     See SV Spec 6.8, pp100.
   }];
  let arguments = (ins StrAttr:$name);
  let results = (outs InOutType:$result);

  let skipDefaultBuilders = 1;
  let builders = [
    OpBuilder<(ins "::mlir::Type":$elementType,
                      CArg<"StringAttr", "StringAttr()">:$name)>
  ];

  // We handle the name in a custom way, so we use a customer parser/printer.
  let assemblyFormat = "custom<ImplicitSSAName>(attr-dict) `:` type($result)";
  let hasCanonicalizeMethod = true;

  let extraClassDeclaration = [{
    Type getElementType() {
      return result().getType().cast<InOutType>().getElementType();
    }
  }];
}

def ReadInOutOp
 : SVOp<"read_inout",
        [NoSideEffect, InOutElementConstraint<"result", "input">]> {
  let summary = "Get the value of from something of inout type (e.g. a wire or"
                " inout port) as the value itself.";
  let arguments = (ins InOutType:$input);
  let results = (outs RTLValueType:$result);

  let builders = [
    OpBuilder<(ins "Value":$input)>
  ];

  let assemblyFormat = "$input attr-dict `:` type($input)";
}

def InOutArrayType
  : Type<CPred<"getAnyRTLArrayElementType(getInOutElementType($_self)) "
                        "!= Type()">,
         "an inout type with array element", "::circt::rtl::InOutType">;

class InOutIndexConstraint<string value, string inoutValue>
  : TypesMatchWith<"type should be element of inout type",
                   inoutValue, value,
                   "InOutType::get(getAnyRTLArrayElementType("
                                            "getInOutElementType($_self)))">;

def ArrayIndexInOutOp
 : SVOp<"array_index_inout",
        [NoSideEffect, InOutIndexConstraint<"result", "input">]> {
  let summary = "Index an inout memory to produce an inout element";
  let description = "See SV Spec 11.5.2.";
  let arguments = (ins InOutArrayType:$input, RTLIntegerType:$index);
  let results = (outs InOutType:$result);

  let builders = [
    OpBuilder<(ins "Value":$input, "Value":$index)>
  ];

  let assemblyFormat =
    "$input`[`$index`]` attr-dict `:` type($input) `,` type($index)";
}
