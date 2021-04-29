//===- FIRRTLOps.cpp - Implement the FIRRTL operations --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implement the FIRRTL ops.
//
//===----------------------------------------------------------------------===//

#include "circt/Dialect/FIRRTL/FIRRTLOps.h"
#include "circt/Dialect/FIRRTL/FIRRTLTypes.h"
#include "circt/Dialect/FIRRTL/FIRRTLVisitors.h"
#include "circt/Dialect/RTL/RTLTypes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/FunctionImplementation.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace circt;
using namespace firrtl;

bool firrtl::isBundleType(Type type) {
  if (auto flipType = type.dyn_cast<FlipType>())
    return flipType.getElementType().isa<FlipType>();
  return type.isa<BundleType>();
}

bool firrtl::isDuplexValue(Value val) {
  Operation *op = val.getDefiningOp();
  // Block arguments are not duplex values.
  if (!op)
    return false;
  return TypeSwitch<Operation *, bool>(op)
      .Case<SubfieldOp, SubindexOp, SubaccessOp>(
          [](auto op) { return isDuplexValue(op.input()); })
      .Case<RegOp, RegResetOp, WireOp>([](auto) { return true; })
      .Default([](auto) { return false; });
}

//===----------------------------------------------------------------------===//
// VERIFY_RESULT_TYPE / VERIFY_RESULT_TYPE_RET
//===----------------------------------------------------------------------===//

// These macros are used to implement verifier hooks that check that the result
// type of a primitive matches what is returned by the getResultType() static
// method.  This should go away when/if this bug is implemented:
//    https://bugs.llvm.org/show_bug.cgi?id=48645
#define VERIFY_RESULT_TYPE(...)                                                \
  {                                                                            \
    auto resType = getResultType(__VA_ARGS__, getLoc());                       \
    if (!resType)                                                              \
      return failure(); /*already diagnosed the error*/                        \
    if (resType != getType())                                                  \
      return emitOpError("result type should be ") << resType;                 \
  }

// This is the same as VERIFY_RESULT_TYPE but return success if the result type
// matches.  This is useful as the last thing in a verify hook.
#define VERIFY_RESULT_TYPE_RET(...)                                            \
  VERIFY_RESULT_TYPE(__VA_ARGS__);                                             \
  return success();

//===----------------------------------------------------------------------===//
// CircuitOp
//===----------------------------------------------------------------------===//

void CircuitOp::build(OpBuilder &builder, OperationState &result,
                      StringAttr name, ArrayAttr annotations) {
  // Add an attribute for the name.
  result.addAttribute(builder.getIdentifier("name"), name);

  if (annotations)
    result.addAttribute("annotations", annotations);

  // Create a region and a block for the body.
  Region *bodyRegion = result.addRegion();
  Block *body = new Block();
  bodyRegion->push_back(body);
}

// Return the main module that is the entry point of the circuit.
Operation *CircuitOp::getMainModule() { return lookupSymbol(name()); }

static LogicalResult verifyCircuitOp(CircuitOp circuit) {
  StringRef main = circuit.name();

  // Check that the circuit has a non-empty name.
  if (main.empty()) {
    circuit.emitOpError("must have a non-empty name");
    return failure();
  }

  // Check that a module matching the "main" module exists in the circuit.
  if (!circuit.getMainModule()) {
    circuit.emitOpError("must contain one module that matches main name '" +
                        main + "'");
    return failure();
  }

  // Store a mapping of defname to either the first external module
  // that defines it or, preferentially, the first external module
  // that defines it and has no parameters.
  llvm::DenseMap<Attribute, FExtModuleOp> defnameMap;

  // Verify external modules.
  for (auto &op : *circuit.getBody()) {
    auto extModule = dyn_cast<FExtModuleOp>(op);
    if (!extModule)
      continue;

    auto defname = extModule.defnameAttr();
    if (!defname)
      continue;

    // Check that this extmodule's defname does not conflict with
    // the symbol name of any module.
    auto collidingModule = circuit.lookupSymbol(defname.getValue());
    if (isa_and_nonnull<FModuleOp>(collidingModule)) {
      auto diag =
          op.emitOpError()
          << "attribute 'defname' with value " << defname
          << " conflicts with the name of another module in the circuit";
      diag.attachNote(collidingModule->getLoc())
          << "previous module declared here";
      return failure();
    }

    // Find an optional extmodule with a defname collision. Update
    // the defnameMap if this is the first extmodule with that
    // defname or if the current extmodule takes no parameters and
    // the collision does. The latter condition improves later
    // extmodule verification as checking against a parameterless
    // module is stricter.
    FExtModuleOp collidingExtModule;
    if (auto &value = defnameMap[defname]) {
      collidingExtModule = value;
      if (value.parameters() && !extModule.parameters())
        value = extModule;
    } else {
      value = extModule;
      // Go to the next extmodule if no extmodule with the same
      // defname was found.
      continue;
    }

    // Check that the number of ports is exactly the same.
    SmallVector<ModulePortInfo> ports = extModule.getPorts();
    SmallVector<ModulePortInfo> collidingPorts = collidingExtModule.getPorts();

    if (ports.size() != collidingPorts.size()) {
      auto diag = op.emitOpError()
                  << "with 'defname' attribute " << defname << " has "
                  << ports.size()
                  << " ports which is different from a previously defined "
                     "extmodule with the same 'defname' which has "
                  << collidingPorts.size() << " ports";
      diag.attachNote(collidingExtModule.getLoc())
          << "previous extmodule definition occurred here";
      return failure();
    }

    // Check that ports match for name and type. Since parameters
    // *might* affect widths, ignore widths if either module has
    // parameters. Note that this allows for misdetections, but
    // has zero false positives.
    for (auto p : llvm::zip(ports, collidingPorts)) {
      StringAttr aName = std::get<0>(p).name, bName = std::get<1>(p).name;
      FIRRTLType aType = std::get<0>(p).type, bType = std::get<1>(p).type;

      if (extModule.parameters() || collidingExtModule.parameters()) {
        aType = aType.getWidthlessType();
        bType = bType.getWidthlessType();
      }
      if (aName != bName) {
        auto diag = op.emitOpError()
                    << "with 'defname' attribute " << defname
                    << " has a port with name " << aName
                    << " which does not match the name of the port "
                    << "in the same position of a previously defined "
                    << "extmodule with the same 'defname', expected port "
                       "to have name "
                    << bName;
        diag.attachNote(collidingExtModule.getLoc())
            << "previous extmodule definition occurred here";
        return failure();
      }
      if (aType != bType) {
        auto diag = op.emitOpError()
                    << "with 'defname' attribute " << defname
                    << " has a port with name " << aName
                    << " which has a different type " << aType
                    << " which does not match the type of the port in "
                       "the same position of a previously defined "
                       "extmodule with the same 'defname', expected port "
                       "to have type "
                    << bType;
        diag.attachNote(collidingExtModule.getLoc())
            << "previous extmodule definition occurred here";
        return failure();
      }
    }
  }

  return success();
}

Region &CircuitOp::getBodyRegion() { return getOperation()->getRegion(0); }
Block *CircuitOp::getBody() { return &getBodyRegion().front(); }

//===----------------------------------------------------------------------===//
// FExtModuleOp and FModuleOp
//===----------------------------------------------------------------------===//

FunctionType firrtl::getModuleType(Operation *op) {
  auto typeAttr = op->getAttrOfType<TypeAttr>(FModuleOp::getTypeAttrName());
  return typeAttr.getValue().cast<FunctionType>();
}

/// This function can extract information about ports from a module and an
/// extmodule.
SmallVector<ModulePortInfo> firrtl::getModulePortInfo(Operation *op) {
  SmallVector<ModulePortInfo> results;
  auto argTypes = getModuleType(op).getInputs();

  auto portNamesAttr = getModulePortNames(op);
  for (unsigned i = 0, e = argTypes.size(); i < e; ++i) {
    auto type = argTypes[i].cast<FIRRTLType>();
    results.push_back({portNamesAttr[i].cast<StringAttr>(), type});
  }
  return results;
}

/// Given an FModule or ExtModule, return the name of the specified port number.
StringAttr firrtl::getModulePortName(Operation *op, size_t portIndex) {
  assert(isa<FModuleOp>(op) || isa<FExtModuleOp>(op));
  return getModulePortNames(op)[portIndex].cast<StringAttr>();
}

static void buildModule(OpBuilder &builder, OperationState &result,
                        StringAttr name, ArrayRef<ModulePortInfo> ports) {
  using namespace mlir::impl;

  // Add an attribute for the name.
  result.addAttribute(::mlir::SymbolTable::getSymbolAttrName(), name);

  SmallVector<Type, 4> argTypes;
  for (auto elt : ports)
    argTypes.push_back(elt.type);

  // Record the argument and result types as an attribute.
  auto type = builder.getFunctionType(argTypes, /*resultTypes*/ {});
  result.addAttribute(getTypeAttrName(), TypeAttr::get(type));

  // Record the names of the arguments if present.
  SmallString<8> attrNameBuf;
  // Record the names of the arguments if present.
  SmallVector<Attribute, 4> portNames;
  for (size_t i = 0, e = ports.size(); i != e; ++i)
    portNames.push_back(ports[i].name);

  result.addAttribute("portNames", builder.getArrayAttr(portNames));

  result.addRegion();
}

void FModuleOp::build(OpBuilder &builder, OperationState &result,
                      StringAttr name, ArrayRef<ModulePortInfo> ports,
                      ArrayAttr annotations) {
  buildModule(builder, result, name, ports);

  // Create a region and a block for the body.
  auto *bodyRegion = result.regions[0].get();
  Block *body = new Block();
  bodyRegion->push_back(body);

  // Add arguments to the body block.
  for (auto elt : ports)
    body->addArgument(elt.type);

  if (annotations)
    result.addAttribute("annotations", annotations);
}

// Return the port with the specified name.
BlockArgument FModuleOp::getPortArgument(size_t portNumber) {
  return getBodyBlock()->getArgument(portNumber);
}

void FExtModuleOp::build(OpBuilder &builder, OperationState &result,
                         StringAttr name, ArrayRef<ModulePortInfo> ports,
                         StringRef defnameAttr, ArrayAttr annotations) {
  buildModule(builder, result, name, ports);
  if (!defnameAttr.empty())
    result.addAttribute("defname", builder.getStringAttr(defnameAttr));

  if (annotations)
    result.addAttribute("annotations", annotations);
}

// TODO: This ia a clone of mlir::impl::printFunctionSignature, refactor it to
// allow this customization.
static void printFunctionSignature2(OpAsmPrinter &p, Operation *op,
                                    ArrayRef<Type> argTypes, bool isVariadic,
                                    ArrayRef<Type> resultTypes,
                                    bool &needportNamesAttr) {
  Region &body = op->getRegion(0);
  bool isExternal = body.empty();
  SmallString<32> resultNameStr;

  p << '(';
  auto portNamesAttr = getModulePortNames(op);
  for (unsigned i = 0, e = argTypes.size(); i < e; ++i) {
    if (i > 0)
      p << ", ";

    auto portName = portNamesAttr[i].cast<StringAttr>().getValue();
    Value argumentValue;
    if (!isExternal) {
      // Get the printed format for the argument name.
      resultNameStr.clear();
      llvm::raw_svector_ostream tmpStream(resultNameStr);
      p.printOperand(body.front().getArgument(i), tmpStream);
      // If the name wasn't printable in a way that agreed with portName, make
      // sure to print out an explicit portNames attribute.
      if (!portName.empty() && tmpStream.str().drop_front() != portName)
        needportNamesAttr = true;
      p << tmpStream.str() << ": ";
    } else if (!portName.empty()) {
      p << '%' << portName << ": ";
    }

    p.printType(argTypes[i]);
    p.printOptionalAttrDict(::mlir::impl::getArgAttrs(op, i));
  }

  if (isVariadic) {
    if (!argTypes.empty())
      p << ", ";
    p << "...";
  }

  p << ')';
}

static void printModuleLikeOp(OpAsmPrinter &p, Operation *op) {
  using namespace mlir::impl;

  FunctionType fnType = getModuleType(op);
  auto argTypes = fnType.getInputs();
  auto resultTypes = fnType.getResults();

  // TODO: Should refactor mlir::impl::printFunctionLikeOp to allow these
  // customizations.  Need to not print the terminator.

  // Print the operation and the function name.
  auto funcName =
      op->getAttrOfType<StringAttr>(::mlir::SymbolTable::getSymbolAttrName())
          .getValue();
  p << op->getName() << ' ';
  p.printSymbolName(funcName);

  bool needportNamesAttr = false;
  printFunctionSignature2(p, op, argTypes, /*isVariadic*/ false, resultTypes,
                          needportNamesAttr);
  SmallVector<StringRef, 3> omittedAttrs;
  if (!needportNamesAttr)
    omittedAttrs.push_back("portNames");
  printFunctionAttributes(p, op, argTypes.size(), resultTypes.size(),
                          omittedAttrs);
}

static void print(OpAsmPrinter &p, FExtModuleOp op) {
  printModuleLikeOp(p, op);
}

static void print(OpAsmPrinter &p, FModuleOp op) {
  printModuleLikeOp(p, op);

  // Print the body if this is not an external function. Since this block does
  // not have terminators, printing the terminator actually just prints the last
  // operation.
  Region &body = op.getBody();
  if (!body.empty())
    p.printRegion(body, /*printEntryBlockArgs=*/false,
                  /*printBlockTerminators=*/true);
}

static ParseResult parseFModuleOp(OpAsmParser &parser, OperationState &result,
                                  bool isExtModule = false) {
  using namespace mlir::impl;

  // TODO: Should refactor mlir::impl::parseFunctionLikeOp to allow these
  // customizations for implicit argument names.  Need to not print the
  // terminator.

  SmallVector<OpAsmParser::OperandType, 4> entryArgs;
  SmallVector<NamedAttrList, 4> portNamesAttrs;
  SmallVector<NamedAttrList, 4> resultAttrs;
  SmallVector<Type, 4> argTypes;
  SmallVector<Type, 4> resultTypes;
  auto &builder = parser.getBuilder();

  // Parse the name as a symbol.
  StringAttr nameAttr;
  if (parser.parseSymbolName(nameAttr, ::mlir::SymbolTable::getSymbolAttrName(),
                             result.attributes))
    return failure();

  // Parse the function signature.
  bool isVariadic = false;
  if (parseFunctionSignature(parser, /*allowVariadic*/ false, entryArgs,
                             argTypes, portNamesAttrs, isVariadic, resultTypes,
                             resultAttrs))
    return failure();

  // Record the argument and result types as an attribute.  This is necessary
  // for external modules.
  auto type = builder.getFunctionType(argTypes, resultTypes);
  result.addAttribute(getTypeAttrName(), TypeAttr::get(type));

  // If function attributes are present, parse them.
  if (parser.parseOptionalAttrDictWithKeyword(result.attributes))
    return failure();

  assert(portNamesAttrs.size() == argTypes.size());
  assert(resultAttrs.size() == resultTypes.size());

  auto *context = result.getContext();

  SmallVector<Attribute> portNames;
  if (!result.attributes.get("portNames")) {
    // Postprocess each of the arguments.  If there was no portNames
    // attribute, and if the argument name was non-numeric, then add the
    // portNames attribute with the textual name from the IR.  The name in the
    // text file is a load-bearing part of the IR, but we don't want the
    // verbosity in dumps of including it explicitly in the attribute
    // dictionary.
    for (size_t i = 0, e = entryArgs.size(); i != e; ++i) {
      auto &arg = entryArgs[i];

      // The name of an argument is of the form "%42" or "%id", and since
      // parsing succeeded, we know it always has one character.
      assert(arg.name.size() > 1 && arg.name[0] == '%' && "Unknown MLIR name");
      if (isdigit(arg.name[1]))
        portNames.push_back(StringAttr::get(context, ""));
      else
        portNames.push_back(StringAttr::get(context, arg.name.drop_front()));
    }
    result.addAttribute("portNames", builder.getArrayAttr(portNames));
  }
  // Add the attributes to the function arguments.
  addArgAndResultAttrs(builder, result, portNamesAttrs, resultAttrs);

  // Parse the optional function body.
  auto *body = result.addRegion();
  if (!isExtModule) {
    if (parser.parseRegion(*body, entryArgs,
                           entryArgs.empty() ? ArrayRef<Type>() : argTypes))
      return failure();
    if (body->empty())
      body->push_back(new Block());
  }
  return success();
}

static ParseResult parseFExtModuleOp(OpAsmParser &parser,
                                     OperationState &result) {
  return parseFModuleOp(parser, result, /*isExtModule:*/ true);
}

static LogicalResult verifyModuleSignature(Operation *op) {
  for (auto argType : getModuleType(op).getInputs())
    if (!argType.isa<FIRRTLType>())
      return op->emitOpError("all module ports must be firrtl types");
  return success();
}

static LogicalResult verifyFModuleOp(FModuleOp op) {
  // Verify the module signature.
  return verifyModuleSignature(op);
}

static LogicalResult verifyFExtModuleOp(FExtModuleOp op) {
  // Verify the module signature.
  if (failed(verifyModuleSignature(op)))
    return failure();

  auto paramDictOpt = op.parameters();
  if (!paramDictOpt)
    return success();

  DictionaryAttr paramDict = paramDictOpt.getValue();
  auto checkParmValue = [&](NamedAttribute elt) -> bool {
    auto value = elt.second;
    if (value.isa<IntegerAttr>() || value.isa<StringAttr>() ||
        value.isa<FloatAttr>())
      return true;
    op.emitError() << "has unknown extmodule parameter value '" << elt.first
                   << "' = " << value;
    return false;
  };

  if (!llvm::all_of(paramDict, checkParmValue))
    return failure();
  auto portNamesAttr = getModulePortNames(op);

  if (op.getPorts().size() != portNamesAttr.size())
    return op.emitError("module ports does not match number of arguments");

  return success();
}

//===----------------------------------------------------------------------===//
// Declarations
//===----------------------------------------------------------------------===//

/// Lookup the module or extmodule for the symbol.  This returns null on
/// invalid IR.
Operation *InstanceOp::getReferencedModule() {
  auto circuit = (*this)->getParentOfType<CircuitOp>();
  if (!circuit)
    return nullptr;

  return circuit.lookupSymbol(moduleName());
}

/// Verify the correctness of an InstanceOp.
static LogicalResult verifyInstanceOp(InstanceOp instance) {

  // Check that this instance is inside a module.
  auto module = instance->getParentOfType<FModuleOp>();
  if (!module) {
    instance.emitOpError("should be embedded in a 'firrtl.module'");
    return failure();
  }

  auto *referencedModule = instance.getReferencedModule();
  if (!referencedModule) {
    instance.emitOpError("invalid symbol reference");
    return failure();
  }

  // Check that this instance doesn't recursively instantiate its wrapping
  // module.
  if (referencedModule == module) {
    auto diag = instance.emitOpError()
                << "is a recursive instantiation of its containing module";
    diag.attachNote(module.getLoc()) << "containing module declared here";
    return failure();
  }

  SmallVector<ModulePortInfo> modulePorts = getModulePortInfo(referencedModule);

  // Check that result types are consistent with the referenced module's ports.
  size_t numResults = instance.getNumResults();
  if (numResults != modulePorts.size()) {
    auto diag = instance.emitOpError()
                << "has a wrong number of results; expected "
                << modulePorts.size() << " but got " << numResults;
    diag.attachNote(referencedModule->getLoc())
        << "original module declared here";
    return failure();
  }

  for (size_t i = 0; i != numResults; i++) {
    auto resultType = instance.getResult(i).getType();
    auto expectedType = FlipType::get(modulePorts[i].type);
    if (resultType != expectedType) {
      auto diag = instance.emitOpError()
                  << "result type for " << modulePorts[i].name << " must be "
                  << expectedType << ", but got " << resultType;

      diag.attachNote(referencedModule->getLoc())
          << "original module declared here";
      return failure();
    }
  }

  return success();
}

/// Verify the correctness of a MemOp.
static LogicalResult verifyMemOp(MemOp mem) {

  // Store the port names as we find them. This lets us check quickly
  // for uniqueneess.
  llvm::SmallDenseSet<Attribute, 8> portNamesSet;

  // Store the previous data type. This lets us check that the data
  // type is consistent across all ports.
  FIRRTLType oldDataType;

  for (size_t i = 0, e = mem.getNumResults(); i != e; ++i) {
    auto portName = mem.getPortName(i);

    // Get a bundle type representing this port, stripping an outer
    // flip if it exists.  If this is not a bundle<> or
    // flip<bundle<>>, then this is an error.
    BundleType portBundleType =
        TypeSwitch<FIRRTLType, BundleType>(
            mem.getResult(i).getType().cast<FIRRTLType>())
            .Case<BundleType>([](BundleType a) { return a; })
            .Case<FlipType>([](FlipType a) {
              return a.getElementType().dyn_cast<BundleType>();
            })
            .Default([](auto) { return nullptr; });
    if (!portBundleType) {
      mem.emitOpError() << "has an invalid type on port " << portName
                        << " (expected either '!firrtl.bundle<...>' or "
                           "'!firrtl.flip<bundle<...>>')";
      return failure();
    }

    // Require that all port names are unique.
    if (!portNamesSet.insert(portName).second) {
      mem.emitOpError() << "has non-unique port name " << portName;
      return failure();
    }

    // Determine the kind of the memory.  If the kind cannot be
    // determined, then it's indicative of the wrong number of fields
    // in the type (but we don't know any more just yet).
    MemOp::PortKind portKind;
    {
      auto portKindOption =
          mem.getPortKind(mem.getPortName(i).getValue().str());
      if (!portKindOption.hasValue()) {
        mem.emitOpError()
            << "has an invalid number of fields on port " << portName
            << " (expected 4 for read, 5 for write, or 7 for read/write)";
        return failure();
      }
      portKind = portKindOption.getValue();
    }

    // Safely search for the "data" field, erroring if it can't be
    // found.
    FIRRTLType dataType;
    {
      auto dataTypeOption = portBundleType.getElement("data");
      if (!dataTypeOption && portKind == MemOp::PortKind::ReadWrite)
        dataTypeOption = portBundleType.getElement("rdata");
      if (!dataTypeOption) {
        mem.emitOpError() << "has no data field on port " << portName
                          << " (expected to see \"data\" for a read or write "
                             "port or \"rdata\" for a read/write port)";
        return failure();
      }
      dataType = dataTypeOption.getValue().type;
    }

    // Error if the data type isn't passive.
    if (!dataType.isPassive()) {
      mem.emitOpError() << "has non-passive data type on port " << portName
                        << " (memory types must be passive)";
      return failure();
    }

    // Error if the data type contains analog types.
    if (dataType.containsAnalog()) {
      mem.emitOpError()
          << "has a data type that contains an analog type on port " << portName
          << " (memory types cannot contain analog types)";
      return failure();
    }

    // Check that the port type matches the kind that we determined
    // for this port.  This catches situations of extraneous port
    // fields beind included or the fields being named incorrectly.
    FIRRTLType expectedType =
        FlipType::get(mem.getTypeForPort(mem.depth(), dataType, portKind));
    // Compute the original port type as portBundleType may have
    // stripped outer flip information.
    auto originalType = mem.getResult(i).getType();
    if (originalType != expectedType) {
      StringRef portKindName;
      switch (portKind) {
      case MemOp::PortKind::Read:
        portKindName = "read";
        break;
      case MemOp::PortKind::Write:
        portKindName = "write";
        break;
      case MemOp::PortKind::ReadWrite:
        portKindName = "readwrite";
        break;
      }
      mem.emitOpError() << "has an invalid type for port " << portName
                        << " of determined kind \"" << portKindName
                        << "\" (expected " << expectedType << ", but got "
                        << originalType << ")";
      return failure();
    }

    // Error if the type of the current port was not the same as the
    // last port, but skip checking the first port.
    if (oldDataType && oldDataType != dataType) {
      mem.emitOpError() << "port " << mem.getPortName(i)
                        << " has a different type than port "
                        << mem.getPortName(i - 1) << " (expected "
                        << oldDataType << ", but got " << dataType << ")";
      return failure();
    }

    oldDataType = dataType;
  }

  return success();
}

BundleType MemOp::getTypeForPort(uint64_t depth, FIRRTLType dataType,
                                 PortKind portKind) {

  auto *context = dataType.getContext();

  auto getId = [&](StringRef name) -> StringAttr {
    return StringAttr::get(context, name);
  };

  SmallVector<BundleType::BundleElement, 7> portFields;

  auto addressType =
      UIntType::get(context, std::max(1U, llvm::Log2_64_Ceil(depth)));

  portFields.push_back({getId("addr"), addressType});
  portFields.push_back({getId("en"), UIntType::get(context, 1)});
  portFields.push_back({getId("clk"), ClockType::get(context)});

  switch (portKind) {
  case PortKind::Read:
    portFields.push_back({getId("data"), FlipType::get(dataType)});
    break;

  case PortKind::Write:
    portFields.push_back({getId("data"), dataType});
    portFields.push_back({getId("mask"), dataType.getMaskType()});
    break;

  case PortKind::ReadWrite:
    portFields.push_back({getId("wmode"), UIntType::get(context, 1)});
    portFields.push_back({getId("rdata"), FlipType::get(dataType)});
    portFields.push_back({getId("wdata"), dataType});
    portFields.push_back({getId("wmask"), dataType.getMaskType()});
    break;
  }

  return BundleType::get(portFields, context).cast<BundleType>();
}

/// Return the kind of port this is given the port type from a 'mem' decl.
static Optional<MemOp::PortKind> getMemPortKindFromType(FIRRTLType type) {
  auto portType = type.dyn_cast<BundleType>();
  if (!portType) {
    if (auto flipType = type.dyn_cast<FlipType>())
      portType = flipType.getElementType().dyn_cast<BundleType>();
    if (!portType)
      return None;
  }
  switch (portType.getNumElements()) {
  default:
    return None;
  case 4:
    return MemOp::PortKind::Read;
  case 5:
    return MemOp::PortKind::Write;
  case 7:
    return MemOp::PortKind::ReadWrite;
  }
}

/// Return the name and kind of ports supported by this memory.
SmallVector<std::pair<Identifier, MemOp::PortKind>> MemOp::getPorts() {
  SmallVector<std::pair<Identifier, MemOp::PortKind>> result;
  // Each entry in the bundle is a port.
  for (size_t i = 0, e = getNumResults(); i != e; ++i) {
    auto elt = getResult(i);
    // Each port is a bundle.
    auto kind = getMemPortKindFromType(elt.getType().cast<FIRRTLType>());
    assert(kind.hasValue() && "unknown port type!");
    result.push_back({Identifier::get(getPortNameStr(i), elt.getContext()),
                      kind.getValue()});
  }
  return result;
}

/// Return the kind of the specified port or None if the name is invalid.
Optional<MemOp::PortKind> MemOp::getPortKind(StringRef portName) {
  auto elt = getPortNamed(portName);
  if (!elt)
    return None;
  return getMemPortKindFromType(elt.getType().cast<FIRRTLType>());
}

/// Return the kind of the specified port number.
Optional<MemOp::PortKind> MemOp::getPortKind(size_t resultNo) {
  return getMemPortKindFromType(
      getResult(resultNo).getType().cast<FIRRTLType>());
}

/// Return the data-type field of the memory, the type of each element.
FIRRTLType MemOp::getDataType() {
  assert(getNumResults() != 0 && "Mems with no read/write ports are illegal");

  auto firstPortType = getResult(0).getType().cast<FIRRTLType>();

  StringRef dataFieldName = "data";
  if (getMemPortKindFromType(firstPortType).getValue() == PortKind::ReadWrite)
    dataFieldName = "rdata";

  return firstPortType.getPassiveType().cast<BundleType>().getElementType(
      dataFieldName);
}

StringAttr MemOp::getPortName(size_t resultNo) {
  return portNames()[resultNo].cast<StringAttr>();
}

FIRRTLType MemOp::getPortType(size_t resultNo) {
  return results()[resultNo].getType().cast<FIRRTLType>();
}

Value MemOp::getPortNamed(StringAttr name) {
  auto namesArray = portNames();
  for (size_t i = 0, e = namesArray.size(); i != e; ++i) {
    if (namesArray[i] == name) {
      assert(i < getNumResults() && " names array out of sync with results");
      return getResult(i);
    }
  }
  return Value();
}

//===----------------------------------------------------------------------===//
// Statements
//===----------------------------------------------------------------------===//

static LogicalResult verifyConnectOp(ConnectOp connect) {
  FIRRTLType destType = connect.dest().getType().cast<FIRRTLType>();
  FIRRTLType srcType = connect.src().getType().cast<FIRRTLType>();

  // Analog types cannot be connected and must be attached.
  if (destType.isa<AnalogType>() || srcType.isa<AnalogType>())
    return connect.emitError("analog types may not be connected");

  // Destination and source types must be equivalent.
  if (!areTypesEquivalent(destType, srcType))
    return connect.emitError("type mismatch between destination ")
           << destType.getPassiveType() << " and source "
           << srcType.getPassiveType();

  // Destination bitwidth must be greater than or equal to source bitwidth.
  int32_t destWidth = destType.getPassiveType().getBitWidthOrSentinel();
  int32_t srcWidth = srcType.getPassiveType().getBitWidthOrSentinel();
  if (destWidth > -1 && srcWidth > -1 && destWidth < srcWidth)
    return connect.emitError("destination width ")
           << destWidth << " is not greater than or equal to source width "
           << srcWidth;

  // Check that the LHS is a valid sink and RHS is a valid source.
  if (isBundleType(destType)) {
    // For bulk connections, we need to make sure that the connection is
    // unambiguous by making sure that both sides are not duplex types. TODO: we
    // are not checking that the connections are recursively well formed when
    // neither is a duplex type.
    if (isDuplexValue(connect.dest()) && isDuplexValue(connect.src())) {
      return connect.emitOpError() << "ambiguous bulk connection between two "
                                   << "duplex values of bundle type";
    }
  } else {
    // This is a mono-connection. Check that the LHS side is a sink or duplex.
    // Since we can read from a either a passive or flip type, we don't need to
    // check anything on the RHS.
    if (destType.isPassive() && !isDuplexValue(connect.dest())) {
      return connect.emitOpError("connection destination must be a non-passive "
                                 "type or a duplex value");
    }
  }

  return success();
}

void WhenOp::createElseRegion() {
  assert(!hasElseRegion() && "already has an else region");
  elseRegion().push_back(new Block());
}

void WhenOp::build(OpBuilder &builder, OperationState &result, Value condition,
                   bool withElseRegion, std::function<void()> thenCtor,
                   std::function<void()> elseCtor) {
  OpBuilder::InsertionGuard guard(builder);
  result.addOperands(condition);

  // Create "then" region.
  builder.createBlock(result.addRegion());
  if (thenCtor)
    thenCtor();

  // Create "else" region.
  Region *elseRegion = result.addRegion();
  if (withElseRegion) {
    builder.createBlock(elseRegion);
    if (elseCtor)
      elseCtor();
  }
}

//===----------------------------------------------------------------------===//
// Expressions
//===----------------------------------------------------------------------===//

/// Return true if the specified operation is a firrtl expression.
bool firrtl::isExpression(Operation *op) {
  struct IsExprClassifier : public ExprVisitor<IsExprClassifier, bool> {
    bool visitInvalidExpr(Operation *op) { return false; }
    bool visitUnhandledExpr(Operation *op) { return true; }
  };

  return IsExprClassifier().dispatchExprVisitor(op);
}

static LogicalResult verifyConstantOp(ConstantOp constant) {
  // If the result type has a bitwidth, then the attribute must match its width.
  auto intType = constant.getType().cast<IntType>();
  auto width = intType.getWidthOrSentinel();
  if (width != -1 && (int)constant.value().getBitWidth() != width)
    return constant.emitError(
        "firrtl.constant attribute bitwidth doesn't match return type");

  return success();
}

/// Build a ConstantOp from an APInt and a FIRRTL type, handling the attribute
/// formation for the 'value' attribute.
void ConstantOp::build(OpBuilder &builder, OperationState &result, IntType type,
                       const APInt &value) {

  int32_t width = type.getWidthOrSentinel();
  assert((width == -1 || (int32_t)value.getBitWidth() == width) &&
         "incorrect attribute bitwidth for firrtl.constant");

  auto signedness =
      type.isSigned() ? IntegerType::Signed : IntegerType::Unsigned;
  Type attrType =
      IntegerType::get(type.getContext(), value.getBitWidth(), signedness);
  auto attr = builder.getIntegerAttr(attrType, value);
  return build(builder, result, type, attr);
}

void SubfieldOp::build(OpBuilder &builder, OperationState &result, Value input,
                       StringRef fieldName) {
  return build(builder, result, input, builder.getStringAttr(fieldName));
}

void SubfieldOp::build(OpBuilder &builder, OperationState &result, Value input,
                       StringAttr fieldName) {
  auto resultType = getResultType(input.getType(), fieldName, input.getLoc());
  assert(resultType && "invalid field name for bundle");
  return build(builder, result, resultType, input, fieldName);
}

// Return the result of a subfield operation.
FIRRTLType SubfieldOp::getResultType(Type inType, StringAttr fieldName,
                                     Location loc) {
  if (auto bundleType = inType.dyn_cast<BundleType>()) {
    for (auto &elt : bundleType.getElements()) {
      if (elt.name == fieldName)
        return elt.type;
    }
    mlir::emitError(loc, "unknown field '")
        << fieldName.getValue() << "' in bundle type " << inType;
    return {};
  }

  if (auto flipType = inType.dyn_cast<FlipType>())
    if (auto subType = getResultType(flipType.getElementType(), fieldName, loc))
      return FlipType::get(subType);

  mlir::emitError(loc, "subfield requires bundle operand");
  return {};
}

FIRRTLType SubindexOp::getResultType(FIRRTLType inType, unsigned fieldIdx,
                                     Location loc) {
  if (auto vectorType = inType.dyn_cast<FVectorType>()) {
    if (fieldIdx < vectorType.getNumElements())
      return vectorType.getElementType();
    mlir::emitError(loc, "out of range index '")
        << fieldIdx << "' in vector type " << inType;
    return {};
  }

  if (auto flipType = inType.dyn_cast<FlipType>())
    if (auto subType = getResultType(flipType.getElementType(), fieldIdx, loc))
      return FlipType::get(subType);

  mlir::emitError(loc, "subindex requires vector operand");
  return {};
}

FIRRTLType SubaccessOp::getResultType(FIRRTLType inType, FIRRTLType indexType,
                                      Location loc) {
  if (!indexType.isa<UIntType>()) {
    mlir::emitError(loc, "subaccess index must be UInt type, not ")
        << indexType;
    return {};
  }

  if (auto vectorType = inType.dyn_cast<FVectorType>())
    return vectorType.getElementType();

  if (auto flipType = inType.dyn_cast<FlipType>())
    if (auto subType = getResultType(flipType.getElementType(), indexType, loc))
      return FlipType::get(subType);

  mlir::emitError(loc, "subaccess requires vector operand, not ") << inType;
  return {};
}

//===----------------------------------------------------------------------===//
// Binary Primitives
//===----------------------------------------------------------------------===//

/// If LHS and RHS are both UInt or SInt types, the return true and fill in the
/// width of them if known.  If unknown, return -1 for the widths.
///
/// On failure, this reports and error and returns false.  This function should
/// not be used if you don't want an error reported.
static bool isSameIntTypeKind(FIRRTLType lhs, FIRRTLType rhs, int32_t &lhsWidth,
                              int32_t &rhsWidth, Location loc) {
  // Must have two integer types with the same signedness.
  auto lhsi = lhs.dyn_cast<IntType>();
  auto rhsi = rhs.dyn_cast<IntType>();
  if (!lhsi || !rhsi || lhsi.isSigned() != rhsi.isSigned()) {
    if (lhsi && !rhsi)
      mlir::emitError(loc, "second operand must be an integer type, not ")
          << rhs;
    else if (!lhsi && rhsi)
      mlir::emitError(loc, "first operand must be an integer type, not ")
          << lhs;
    else if (!lhsi && !rhsi)
      mlir::emitError(loc, "operands must be integer types, not ")
          << lhs << " and " << rhs;
    else
      mlir::emitError(loc, "operand signedness must match");
    return false;
  }

  lhsWidth = lhsi.getWidthOrSentinel();
  rhsWidth = rhs.cast<IntType>().getWidthOrSentinel();
  return true;
}

static FIRRTLType getAddSubResult(FIRRTLType lhs, FIRRTLType rhs,
                                  Location loc) {
  int32_t lhsWidth, rhsWidth, resultWidth = -1;
  if (!isSameIntTypeKind(lhs, rhs, lhsWidth, rhsWidth, loc))
    return {};

  if (lhsWidth != -1 && rhsWidth != -1)
    resultWidth = std::max(lhsWidth, rhsWidth) + 1;
  return IntType::get(lhs.getContext(), lhs.isa<SIntType>(), resultWidth);
}

FIRRTLType AddPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  return getAddSubResult(lhs, rhs, loc);
}

FIRRTLType SubPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  return getAddSubResult(lhs, rhs, loc);
}

FIRRTLType MulPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  int32_t lhsWidth, rhsWidth, resultWidth = -1;
  if (!isSameIntTypeKind(lhs, rhs, lhsWidth, rhsWidth, loc))
    return {};

  if (lhsWidth != -1 && rhsWidth != -1)
    resultWidth = lhsWidth + rhsWidth;

  return IntType::get(lhs.getContext(), lhs.isa<SIntType>(), resultWidth);
}

FIRRTLType DivPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  int32_t lhsWidth, rhsWidth;
  if (!isSameIntTypeKind(lhs, rhs, lhsWidth, rhsWidth, loc))
    return {};

  // For unsigned, the width is the width of the numerator on the LHS.
  if (lhs.isa<UIntType>())
    return UIntType::get(lhs.getContext(), lhsWidth);

  // For signed, the width is the width of the numerator on the LHS, plus 1.
  int32_t resultWidth = lhsWidth != -1 ? lhsWidth + 1 : -1;
  return SIntType::get(lhs.getContext(), resultWidth);
}

FIRRTLType RemPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  int32_t lhsWidth, rhsWidth, resultWidth = -1;
  if (!isSameIntTypeKind(lhs, rhs, lhsWidth, rhsWidth, loc))
    return {};

  if (lhsWidth != -1 && rhsWidth != -1)
    resultWidth = std::min(lhsWidth, rhsWidth);
  return IntType::get(lhs.getContext(), lhs.isa<SIntType>(), resultWidth);
}

static FIRRTLType getBitwiseBinaryResult(FIRRTLType lhs, FIRRTLType rhs,
                                         Location loc) {
  int32_t lhsWidth, rhsWidth, resultWidth = -1;
  if (!isSameIntTypeKind(lhs, rhs, lhsWidth, rhsWidth, loc))
    return {};

  if (lhsWidth != -1 && rhsWidth != -1)
    resultWidth = std::max(lhsWidth, rhsWidth);
  return UIntType::get(lhs.getContext(), resultWidth);
}

FIRRTLType AndPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  return getBitwiseBinaryResult(lhs, rhs, loc);
}
FIRRTLType OrPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                   Location loc) {
  return getBitwiseBinaryResult(lhs, rhs, loc);
}
FIRRTLType XorPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  return getBitwiseBinaryResult(lhs, rhs, loc);
}

static FIRRTLType getCompareResult(FIRRTLType lhs, FIRRTLType rhs,
                                   Location loc) {
  int32_t lhsWidth, rhsWidth;
  if (!isSameIntTypeKind(lhs, rhs, lhsWidth, rhsWidth, loc))
    return {};

  return UIntType::get(lhs.getContext(), 1);
}

FIRRTLType LEQPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  return getCompareResult(lhs, rhs, loc);
}
FIRRTLType LTPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                   Location loc) {
  return getCompareResult(lhs, rhs, loc);
}
FIRRTLType GEQPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  return getCompareResult(lhs, rhs, loc);
}
FIRRTLType GTPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                   Location loc) {
  return getCompareResult(lhs, rhs, loc);
}
FIRRTLType EQPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                   Location loc) {
  return getCompareResult(lhs, rhs, loc);
}
FIRRTLType NEQPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  return getCompareResult(lhs, rhs, loc);
}

FIRRTLType CatPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                    Location loc) {
  int32_t lhsWidth, rhsWidth, resultWidth = -1;
  if (!isSameIntTypeKind(lhs, rhs, lhsWidth, rhsWidth, loc))
    return {};

  if (lhsWidth != -1 && rhsWidth != -1)
    resultWidth = lhsWidth + rhsWidth;
  return UIntType::get(lhs.getContext(), resultWidth);
}

FIRRTLType DShlPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                     Location loc) {
  auto lhsi = lhs.dyn_cast<IntType>();
  auto rhsui = rhs.dyn_cast<UIntType>();
  if (!rhsui || !lhsi) {
    mlir::emitError(loc,
                    "first operand should be integer, second unsigned int");
    return {};
  }

  // If the left or right has unknown result type, then the operation does
  // too.
  auto width = lhsi.getWidthOrSentinel();
  if (width == -1 || !rhsui.getWidth().hasValue())
    width = -1;
  else
    width = width + (1 << rhsui.getWidth().getValue()) - 1;
  return IntType::get(lhs.getContext(), lhsi.isSigned(), width);
}

FIRRTLType DShlwPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                      Location loc) {
  if (!lhs.isa<IntType>() || !rhs.isa<UIntType>()) {
    mlir::emitError(loc,
                    "first operand should be integer, second unsigned int");
    return {};
  }
  return lhs;
}

FIRRTLType DShrPrimOp::getResultType(FIRRTLType lhs, FIRRTLType rhs,
                                     Location loc) {
  if (!lhs.isa<IntType>() || !rhs.isa<UIntType>()) {
    mlir::emitError(loc,
                    "first operand should be integer, second unsigned int");
    return {};
  }
  return lhs;
}

//===----------------------------------------------------------------------===//
// Unary Primitives
//===----------------------------------------------------------------------===//

FIRRTLType AsSIntPrimOp::getResultType(FIRRTLType input, Location loc) {
  int32_t width = input.getBitWidthOrSentinel();
  if (width == -2) {
    mlir::emitError(loc, "operand must be a scalar type");
    return {};
  }

  return SIntType::get(input.getContext(), width);
}

FIRRTLType AsUIntPrimOp::getResultType(FIRRTLType input, Location loc) {
  int32_t width = input.getBitWidthOrSentinel();
  if (width == -2) {
    mlir::emitError(loc, "operand must be a scalar type");
    return {};
  }

  return UIntType::get(input.getContext(), width);
}

FIRRTLType AsAsyncResetPrimOp::getResultType(FIRRTLType input, Location loc) {
  int32_t width = input.getBitWidthOrSentinel();
  if (width == -2 || width == 0 || width > 1) {
    mlir::emitError(loc, "operand must be single bit scalar type");
    return {};
  }
  return AsyncResetType::get(input.getContext());
}

FIRRTLType AsClockPrimOp::getResultType(FIRRTLType input, Location loc) {
  int32_t width = input.getBitWidthOrSentinel();
  if (width == -2 || width == 0 || width > 1) {
    mlir::emitError(loc, "operand must be single bit scalar type");
    return {};
  }
  return ClockType::get(input.getContext());
}

FIRRTLType CvtPrimOp::getResultType(FIRRTLType input, Location loc) {
  if (auto uiType = input.dyn_cast<UIntType>()) {
    auto width = uiType.getWidthOrSentinel();
    if (width != -1)
      ++width;
    return SIntType::get(input.getContext(), width);
  }

  if (input.isa<SIntType>())
    return input;

  mlir::emitError(loc, "operand must have integer type");
  return {};
}

FIRRTLType NegPrimOp::getResultType(FIRRTLType input, Location loc) {
  auto inputi = input.dyn_cast<IntType>();
  if (!inputi) {
    mlir::emitError(loc, "operand must have integer type");

    return {};
  }
  int32_t width = inputi.getWidthOrSentinel();
  if (width != -1)
    ++width;
  return SIntType::get(input.getContext(), width);
}

FIRRTLType NotPrimOp::getResultType(FIRRTLType input, Location loc) {
  auto inputi = input.dyn_cast<IntType>();
  if (!inputi) {
    mlir::emitError(loc, "operand must have integer type");

    return {};
  }
  return UIntType::get(input.getContext(), inputi.getWidthOrSentinel());
}

static FIRRTLType getReductionResult(FIRRTLType input, Location loc) {
  if (!input.isa<IntType>()) {
    mlir::emitError(loc, "operand must have integer type");
    return {};
  }
  return UIntType::get(input.getContext(), 1);
}

FIRRTLType AndRPrimOp::getResultType(FIRRTLType input, Location loc) {
  return getReductionResult(input, loc);
}
FIRRTLType OrRPrimOp::getResultType(FIRRTLType input, Location loc) {
  return getReductionResult(input, loc);
}
FIRRTLType XorRPrimOp::getResultType(FIRRTLType input, Location loc) {
  return getReductionResult(input, loc);
}

//===----------------------------------------------------------------------===//
// Other Operations
//===----------------------------------------------------------------------===//

FIRRTLType BitsPrimOp::getResultType(FIRRTLType input, int32_t high,
                                     int32_t low, Location loc) {
  auto inputi = input.dyn_cast<IntType>();

  if (!inputi) {
    mlir::emitError(loc, "input type should be the int type but got ") << input;
    return {};
  }

  // High must be >= low and both most be non-negative.
  if (high < low) {
    mlir::emitError(loc,
                    "high must be equal or greater than low, but got high = ")
        << high << ", low = " << low;
    return {};
  }

  if (low < 0) {
    mlir::emitError(loc, "low must be non-negative but got ") << low;
    return {};
  }

  // If the input has staticly known width, check it.  Both and low must be
  // strictly less than width.
  int32_t width = inputi.getWidthOrSentinel();
  if (width != -1 && high >= width) {
    mlir::emitError(loc)
        << "high must be smaller than the width of input, but got high = "
        << high << ", width = " << width;
    return {};
  }

  return UIntType::get(input.getContext(), high - low + 1);
}

void BitsPrimOp::build(OpBuilder &builder, OperationState &result, Value input,
                       unsigned high, unsigned low) {
  auto type = getResultType(input.getType().cast<FIRRTLType>(), high, low,
                            result.location);
  assert(type && "invalid inputs building BitsPrimOp!");
  build(builder, result, type, input, high, low);
}

FIRRTLType HeadPrimOp::getResultType(FIRRTLType input, int32_t amount,
                                     Location loc) {
  auto inputi = input.dyn_cast<IntType>();
  if (amount < 0 || !inputi) {
    mlir::emitError(loc,
                    "operand must have integer type and amount must be >= 0");
    return {};
  }

  int32_t width = inputi.getWidthOrSentinel();
  if (width != -1 && amount > width) {
    mlir::emitError(loc, "amount larger than input width");
    return {};
  }

  width = std::max(width, amount);
  return UIntType::get(input.getContext(), amount);
}

FIRRTLType MuxPrimOp::getResultType(FIRRTLType sel, FIRRTLType high,
                                    FIRRTLType low, Location loc) {
  // Sel needs to be a one bit uint or an unknown width uint.
  auto selui = sel.dyn_cast<UIntType>();
  int32_t selWidth = selui.getBitWidthOrSentinel();
  if (!selui || selWidth == 0 || selWidth > 1) {
    mlir::emitError(loc, "selector must be UInt or UInt<1>");
    return {};
  }

  // TODO: Should use a more general type equivalence operator.
  if (high == low)
    return low;

  // The base types need to be equivalent.
  if (high.getTypeID() != low.getTypeID()) {
    mlir::emitError(loc, "true and false value must have same type");
    return {};
  }

  if (low.isa<IntType>()) {
    // Two different Int types can be compatible.  If either has unknown
    // width, then return it.  If both are known but different width, then
    // return the larger one.
    int32_t highWidth = high.getBitWidthOrSentinel();
    int32_t lowWidth = low.getBitWidthOrSentinel();
    if (lowWidth == -1)
      return low;
    if (highWidth == -1)
      return high;
    return lowWidth > highWidth ? low : high;
  }

  // FIXME: Should handle bundles and other things.
  mlir::emitError(loc, "unknown types to mux");
  return {};
}

FIRRTLType PadPrimOp::getResultType(FIRRTLType input, int32_t amount,
                                    Location loc) {
  auto inputi = input.dyn_cast<IntType>();
  if (amount < 0 || !inputi) {
    mlir::emitError(loc, "input must be integer and amount must be >= 0");
    return {};
  }

  int32_t width = inputi.getWidthOrSentinel();
  if (width == -1)
    return input;

  width = std::max(width, amount);
  return IntType::get(input.getContext(), inputi.isSigned(), width);
}

FIRRTLType ShlPrimOp::getResultType(FIRRTLType input, int32_t amount,
                                    Location loc) {
  auto inputi = input.dyn_cast<IntType>();
  if (amount < 0 || !inputi) {
    mlir::emitError(loc, "input must be integer and amount must be >= 0");
    return {};
  }

  int32_t width = inputi.getWidthOrSentinel();
  if (width != -1)
    width += amount;

  return IntType::get(input.getContext(), inputi.isSigned(), width);
}

FIRRTLType ShrPrimOp::getResultType(FIRRTLType input, int32_t amount,
                                    Location loc) {
  auto inputi = input.dyn_cast<IntType>();
  if (amount < 0 || !inputi) {
    mlir::emitError(loc, "input must be integer and amount must be >= 0");
    return {};
  }

  int32_t width = inputi.getWidthOrSentinel();
  if (width != -1)
    width = std::max(1, width - amount);

  return IntType::get(input.getContext(), inputi.isSigned(), width);
}

FIRRTLType TailPrimOp::getResultType(FIRRTLType input, int32_t amount,
                                     Location loc) {
  auto inputi = input.dyn_cast<IntType>();
  if (amount < 0 || !inputi) {
    mlir::emitError(loc, "input must be integer and amount must be >= 0");
    return {};
  }

  int32_t width = inputi.getWidthOrSentinel();
  if (width != -1) {
    if (width < amount) {
      mlir::emitError(loc, "amount must be less than or equal operand width");
      return {};
    }
    width -= amount;
  }

  return IntType::get(input.getContext(), false, width);
}

//===----------------------------------------------------------------------===//
// Conversions to/from fixed-width signless integer types in standard dialect.
//===----------------------------------------------------------------------===//

static LogicalResult verifyStdIntCastOp(StdIntCastOp cast) {
  // Either the input or result must have signless standard integer type, the
  // other must be a FIRRTL type that lowers to one, and their widths must
  // match.
  FIRRTLType firType;
  IntegerType integerType;
  if ((firType = cast.getOperand().getType().dyn_cast<FIRRTLType>())) {
    integerType = cast.getType().dyn_cast<IntegerType>();
    if (!integerType)
      return cast.emitError("result type must be a signless integer");
  } else if ((firType = cast.getType().dyn_cast<FIRRTLType>())) {
    integerType = cast.getOperand().getType().dyn_cast<IntegerType>();
    if (!integerType)
      return cast.emitError("operand type must be a signless integer");
  } else {
    return cast.emitError("either source or result type must be integer type");
  }

  int32_t intWidth = firType.getBitWidthOrSentinel();
  if (intWidth == -2)
    return cast.emitError("firrtl type isn't simple bit type");
  if (intWidth == -1)
    return cast.emitError("SInt/UInt type must have a width");
  if (!integerType.isSignless())
    return cast.emitError("standard integer type must be signless");
  if (unsigned(intWidth) != integerType.getWidth())
    return cast.emitError("source and result width must match");

  return success();
}

static LogicalResult verifyAnalogInOutCastOp(AnalogInOutCastOp cast) {
  AnalogType firType;
  rtl::InOutType inoutType;

  if ((firType = cast.getOperand().getType().dyn_cast<AnalogType>())) {
    inoutType = cast.getType().dyn_cast<rtl::InOutType>();
    if (!inoutType)
      return cast.emitError("result type must be an inout type");
  } else if ((firType = cast.getType().dyn_cast<AnalogType>())) {
    inoutType = cast.getOperand().getType().dyn_cast<rtl::InOutType>();
    if (!inoutType)
      return cast.emitError("operand type must be an inout type");
  } else {
    return cast.emitError("either source or result type must be analog type");
  }

  // The inout type must wrap an integer.
  auto integerType = inoutType.getElementType().dyn_cast<IntegerType>();
  if (!integerType)
    return cast.emitError("inout type must wrap an integer");

  int32_t width = firType.getBitWidthOrSentinel();
  if (width == -2)
    return cast.emitError("firrtl type isn't simple bit type");
  if (width == -1)
    return cast.emitError("Analog type must have a width");
  if (!integerType.isSignless())
    return cast.emitError("standard integer type must be signless");
  if (unsigned(width) != integerType.getWidth())
    return cast.emitError("source and result width must match");

  return success();
}

//===----------------------------------------------------------------------===//
// Conversions to/from structs in the standard dialect.
//===----------------------------------------------------------------------===//

static LogicalResult verifyRTLStructCastOp(RTLStructCastOp cast) {
  // We must have a bundle and a struct, with matching pairwise fields
  BundleType bundleType;
  rtl::StructType structType;
  if ((bundleType = cast.getOperand().getType().dyn_cast<BundleType>())) {
    structType = cast.getType().dyn_cast<rtl::StructType>();
    if (!structType)
      return cast.emitError("result type must be a struct");
  } else if ((bundleType = cast.getType().dyn_cast<BundleType>())) {
    structType = cast.getOperand().getType().dyn_cast<rtl::StructType>();
    if (!structType)
      return cast.emitError("operand type must be a struct");
  } else {
    return cast.emitError("either source or result type must be a bundle type");
  }

  auto firFields = bundleType.getElements();
  auto rtlFields = structType.getElements();
  if (firFields.size() != rtlFields.size())
    return cast.emitError("bundle and struct have different number of fields");

  for (size_t findex = 0, fend = firFields.size(); findex < fend; ++findex) {
    if (firFields[findex].name.getValue() != rtlFields[findex].name)
      return cast.emitError("field names don't match '")
             << firFields[findex].name.getValue() << "', '"
             << rtlFields[findex].name << "'";
    int64_t firWidth =
        FIRRTLType(firFields[findex].type).getBitWidthOrSentinel();
    int64_t rtlWidth = rtl::getBitWidth(rtlFields[findex].type);
    if (firWidth > 0 && rtlWidth > 0 && firWidth != rtlWidth)
      return cast.emitError("size of field '")
             << rtlFields[findex].name << "' don't match " << firWidth << ", "
             << rtlWidth;
  }

  return success();
}

void AsPassivePrimOp::build(OpBuilder &builder, OperationState &result,
                            Value input) {
  result.addOperands(input);
  result.addTypes(input.getType().cast<FIRRTLType>().getPassiveType());
}

//===----------------------------------------------------------------------===//
// ImplicitSSAName Custom Directive
//===----------------------------------------------------------------------===//

static ParseResult parseImplicitSSAName(OpAsmParser &parser,
                                        NamedAttrList &resultAttrs) {

  if (parser.parseOptionalAttrDict(resultAttrs))
    return failure();

  // If the attribute dictionary contains no 'name' attribute, infer it from
  // the SSA name (if specified).
  bool hadName = llvm::any_of(
      resultAttrs, [](NamedAttribute attr) { return attr.first == "name"; });

  // If there was no name specified, check to see if there was a useful name
  // specified in the asm file.
  if (hadName)
    return success();

  auto resultName = parser.getResultName(0).first;
  if (!resultName.empty() && isdigit(resultName[0]))
    resultName = "";
  auto nameAttr = parser.getBuilder().getStringAttr(resultName);
  auto *context = parser.getBuilder().getContext();
  resultAttrs.push_back({Identifier::get("name", context), nameAttr});
  return success();
}

static void printImplicitSSAName(OpAsmPrinter &p, Operation *op,
                                 DictionaryAttr attr) {
  // List of attributes to elide when printing the dictionary.
  SmallVector<StringRef, 2> elides;

  // Note that we only need to print the "name" attribute if the asmprinter
  // result name disagrees with it.  This can happen in strange cases, e.g.
  // when there are conflicts.
  SmallString<32> resultNameStr;
  llvm::raw_svector_ostream tmpStream(resultNameStr);
  p.printOperand(op->getResult(0), tmpStream);
  auto actualName = tmpStream.str().drop_front();
  auto expectedName = op->getAttrOfType<StringAttr>("name").getValue();
  // Anonymous names are printed as digits, which is fine.
  if (actualName == expectedName ||
      (expectedName.empty() && isdigit(actualName[0])))
    elides.push_back("name");

  // Elide "annotations" if it doesn't exist or if it is empty
  auto annotationsAttr = op->getAttrOfType<ArrayAttr>("annotations");
  if (!annotationsAttr || annotationsAttr.empty())
    elides.push_back("annotations");

  p.printOptionalAttrDict(op->getAttrs(), elides);
}

//===----------------------------------------------------------------------===//
// Custom attr-dict Directive that Elides Annotations
//===----------------------------------------------------------------------===//

static ParseResult parseElideAnnotations(OpAsmParser &parser,
                                         NamedAttrList &resultAttrs) {
  return parser.parseOptionalAttrDict(resultAttrs);
}

static void printElideAnnotations(OpAsmPrinter &p, Operation *op,
                                  DictionaryAttr attr) {
  // Elide "annotations" if it doesn't exist or if it is empty
  auto annotationsAttr = op->getAttrOfType<ArrayAttr>("annotations");
  if (!annotationsAttr || annotationsAttr.empty())
    return p.printOptionalAttrDict(op->getAttrs(), {"annotations"});

  p.printOptionalAttrDict(op->getAttrs());
}

//===----------------------------------------------------------------------===//
// InstanceOp Custom attr-dict Directive
//===----------------------------------------------------------------------===//

/// No change from normal parsing.
static ParseResult parseInstanceOp(OpAsmParser &parser,
                                   NamedAttrList &resultAttrs) {
  return parser.parseOptionalAttrDict(resultAttrs);
}

/// Always elide "moduleName" and elide "annotations" if it exists or
/// if it is empty.
static void printInstanceOp(OpAsmPrinter &p, Operation *op,
                            DictionaryAttr attr) {

  // "moduleName" is always elided
  SmallVector<StringRef, 2> elides = {"moduleName"};

  // Elide "annotations" if it doesn't exist or if it is empty
  auto annotationsAttr = op->getAttrOfType<ArrayAttr>("annotations");
  if (!annotationsAttr || annotationsAttr.empty())
    elides.push_back("annotations");

  p.printOptionalAttrDict(op->getAttrs(), elides);
}

//===----------------------------------------------------------------------===//
// MemOp Custom attr-dict Directive
//===----------------------------------------------------------------------===//

/// No change from normal parsing.
static ParseResult parseMemOp(OpAsmParser &parser, NamedAttrList &resultAttrs) {
  return parser.parseOptionalAttrDict(resultAttrs);
}

/// Always elide "ruw" and elide "annotations" if it exists or if it is empty.
static void printMemOp(OpAsmPrinter &p, Operation *op, DictionaryAttr attr) {
  SmallVector<StringRef, 2> elides = {"ruw"};

  auto annotationsAttr = op->getAttrOfType<ArrayAttr>("annotations");
  if (!annotationsAttr || annotationsAttr.empty())
    elides.push_back("annotations");

  p.printOptionalAttrDict(op->getAttrs(), elides);
}

//===----------------------------------------------------------------------===//
// TblGen Generated Logic.
//===----------------------------------------------------------------------===//

// Provide the autogenerated implementation guts for the Op classes.
#define GET_OP_CLASSES
#include "circt/Dialect/FIRRTL/FIRRTL.cpp.inc"
