//===- Combinational.td - combinational logic ops ----------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This describes the MLIR ops for combinational logic.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Arithmetic and Logical Operations
//===----------------------------------------------------------------------===//

// Base class for binary operators.
class BinOp<string mnemonic, list<OpTrait> traits = []> :
      CombOp<mnemonic, traits # [NoSideEffect]> {
  let arguments = (ins CombIntegerType:$lhs, CombIntegerType:$rhs);
  let results = (outs CombIntegerType:$result);

  let assemblyFormat =
    "$lhs `,` $rhs  attr-dict `:` functional-type($args, $results)";
}

// Binary operator with uniform input/result types.
class UTBinOp<string mnemonic, list<OpTrait> traits = []> :
      BinOp<mnemonic,
               traits # [SameTypeOperands, SameOperandsAndResultType]> {
  let assemblyFormat = "$lhs `,` $rhs  attr-dict `:` type($result)";
}

// Base class for variadic operators.
class VariadicOp<string mnemonic, list<OpTrait> traits = []> :
      CombOp<mnemonic, traits # [NoSideEffect]> {
  let arguments = (ins Variadic<CombIntegerType>:$inputs);
  let results = (outs CombIntegerType:$result);

  let assemblyFormat =
    "$inputs attr-dict `:` functional-type($inputs, results)";
}

class UTVariadicOp<string mnemonic, list<OpTrait> traits = []> :
      VariadicOp<mnemonic,
                    traits # [SameTypeOperands, SameOperandsAndResultType]> {

  let hasCanonicalizeMethod = true;
  let hasFolder = true;
  let verifier =  "return ::verifyUTVariadicOp(*this);";

  let assemblyFormat = "$inputs attr-dict `:` type($result)";

  let builders = [
    OpBuilder<(ins "Value":$lhs, "Value":$rhs), [{
      return build($_builder, $_state, lhs.getType(),
                   ValueRange{lhs, rhs}, ArrayRef<NamedAttribute>{});
    }]>
  ];
}

// Arithmetic and Logical Operations.
def AddOp : UTVariadicOp<"add", [Commutative]>;
def MulOp : UTVariadicOp<"mul", [Commutative]>;
def DivUOp : UTBinOp<"divu">;
def DivSOp : UTBinOp<"divs">;
def ModUOp : UTBinOp<"modu">;
def ModSOp : UTBinOp<"mods">;
let hasFolder = true in {
  def ShlOp : UTBinOp<"shl">;
  def ShrUOp : UTBinOp<"shru">;
  def ShrSOp : UTBinOp<"shrs">;
  def SubOp : UTBinOp<"sub">;
}

def AndOp : UTVariadicOp<"and", [Commutative]>;
def OrOp  : UTVariadicOp<"or", [Commutative]>;
def XorOp : UTVariadicOp<"xor", [Commutative]>;

def MergeOp : UTVariadicOp<"merge", [Commutative]> {
  let summary ="Electrically merge signals together as if connected by a wire.";
  let description = [{
    This operation merges multiple signals together as if they were connected to
    a single wire.  Presumably at most one of them should be a Z state at any
    given time otherwise you'd get a short circuit.

    This operation allows modeling multiconnect semantics in SSA.
    ```
      %result = rtl.merge %a, %b, %c : t1
    ```
    }];
  let hasCanonicalizeMethod = false;
}

//===----------------------------------------------------------------------===//
// Comparisons
//===----------------------------------------------------------------------===//

def ICmpPredicateEQ  : I64EnumAttrCase<"eq", 0>;
def ICmpPredicateNE  : I64EnumAttrCase<"ne", 1>;
def ICmpPredicateSLT : I64EnumAttrCase<"slt", 2>;
def ICmpPredicateSLE : I64EnumAttrCase<"sle", 3>;
def ICmpPredicateSGT : I64EnumAttrCase<"sgt", 4>;
def ICmpPredicateSGE : I64EnumAttrCase<"sge", 5>;
def ICmpPredicateULT : I64EnumAttrCase<"ult", 6>;
def ICmpPredicateULE : I64EnumAttrCase<"ule", 7>;
def ICmpPredicateUGT : I64EnumAttrCase<"ugt", 8>;
def ICmpPredicateUGE : I64EnumAttrCase<"uge", 9>;
def ICmpPredicate : I64EnumAttr<
    "ICmpPredicate",
    "rtl.icmp comparison predicate",
    [ICmpPredicateEQ, ICmpPredicateNE, ICmpPredicateSLT, ICmpPredicateSLE,
     ICmpPredicateSGT, ICmpPredicateSGE, ICmpPredicateULT, ICmpPredicateULE,
     ICmpPredicateUGT, ICmpPredicateUGE]>;

def ICmpOp : CombOp<"icmp", [NoSideEffect, SameTypeOperands]> {
  let summary = "Compare two integer values";
  let description = [{
    This operation compares two integers using a predicate.  If the predicate is
    true, returns 1, otherwise returns 0. This operation always returns a one
    bit wide result.

    ```
        %r = rtl.icmp eq %a, %b : i4
    ```
  }];

  let arguments = (ins ICmpPredicate:$predicate, 
                   CombIntegerType:$lhs, CombIntegerType:$rhs);
  let results = (outs I1:$result);

  let assemblyFormat = "$predicate $lhs `,` $rhs  attr-dict `:` type($lhs)";
  
  let hasFolder = true;
  let hasCanonicalizeMethod = true;

  let builders = [
    OpBuilder<(ins "ICmpPredicate":$pred, "Value":$lhs, "Value":$rhs), [{
      return build($_builder, $_state, $_builder.getI1Type(), pred, lhs, rhs);
    }]>
  ];
  let extraClassDeclaration = [{
    /// Returns the flipped predicate, reversing the LHS and RHS operands.  The
    /// lhs and rhs operands should be flipped to match the new predicate.
    static ICmpPredicate getFlippedPredicate(ICmpPredicate predicate);
  }];
}

//===----------------------------------------------------------------------===//
// Unary Operations
//===----------------------------------------------------------------------===//

// Base class for unary reduction operations that produce an i1.
class UnaryI1ReductionOp<string mnemonic, list<OpTrait> traits = []> :
      CombOp<mnemonic, traits # [NoSideEffect]> {
  let arguments = (ins CombIntegerType:$input);
  let results = (outs I1:$result);
  let hasFolder = 1;

  let assemblyFormat = "$input attr-dict `:` type($input)";
}

def ParityOp : UnaryI1ReductionOp<"parity">;

//===----------------------------------------------------------------------===//
// Integer width modifying operations.
//===----------------------------------------------------------------------===//

// Extract a range of bits from the specified input.
def ExtractOp : CombOp<"extract", [NoSideEffect]> {
  let summary = "Extract a range of bits into a smaller value, lowBit "
                "specifies the lowest bit included.";

  let arguments = (ins CombIntegerType:$input, I32Attr:$lowBit);
  let results = (outs CombIntegerType:$result);

  let assemblyFormat =
    "$input `from` $lowBit attr-dict `:` functional-type($input, $result)";

  let hasFolder = true;
  let verifier = "return ::verifyExtractOp(*this);";
}

def SExtOp : CombOp<"sext", [NoSideEffect]> {
  let summary = "Sign extend an integer to an equal or larger integer";

  let arguments = (ins CombIntegerType:$input);
  let results = (outs CombIntegerType:$result);

  let assemblyFormat =
    "$input attr-dict `:` functional-type($input, $result)";

  let hasFolder = true;
  let verifier = "return ::verifySExtOp(*this);";
}

//===----------------------------------------------------------------------===//
// Other Operations
//===----------------------------------------------------------------------===//

def ConcatOp : VariadicOp<"concat"> {
  let summary = "Concatenate a variadic list of operands together.";
  let description = [{
    See the RTL-SV rationale document for details on operand ordering.
  }];

  let hasFolder = true;
  let hasCanonicalizeMethod = true;

  let builders = [
    OpBuilder<(ins "ValueRange":$inputs)>,
    OpBuilder<(ins "Value":$lhs, "Value":$rhs), [{
      return build($_builder, $_state, ValueRange{lhs, rhs});
    }]>
  ];
}

// Select one of two values based on a condition.
def MuxOp : CombOp<"mux",
 [NoSideEffect, AllTypesMatch<["trueValue", "falseValue", "result"]>]> {
  let summary = "Return one or the other operand depending on a selector bit";
  let description = [{
    ```
      %0 = mux %pred, %tvalue, %fvalue : i4
    ```
  }];

  let arguments = (ins I1:$cond, AnyType:$trueValue,
                       AnyType:$falseValue);
  let results = (outs AnyType:$result);

  let assemblyFormat =
    "$cond `,` $trueValue `,` $falseValue attr-dict `:` type($result)";
  
  let hasFolder = true;
  let hasCanonicalizeMethod = true;

  let builders = [
    OpBuilder<(ins "Value":$cond, "Value":$trueValue, "Value":$falseValue),
    [{
      assert(trueValue.getType() == falseValue.getType() &&
             "mux requires matching true/false value types");
      return build($_builder, $_state, trueValue.getType(),
                   cond, trueValue, falseValue);
    }]>
  ];
}
