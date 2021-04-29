//===- firtool.cpp - The firtool utility for working with .fir files ------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements 'firtool', which composes together a variety of
// libraries in a way that is convenient to work with as a user.
//
//===----------------------------------------------------------------------===//

#include "circt/Conversion/Passes.h"
#include "circt/Dialect/Comb/CombDialect.h"
#include "circt/Dialect/FIRRTL/FIRParser.h"
#include "circt/Dialect/FIRRTL/FIRRTLDialect.h"
#include "circt/Dialect/FIRRTL/FIRRTLOps.h"
#include "circt/Dialect/FIRRTL/Passes.h"
#include "circt/Dialect/RTL/RTLDialect.h"
#include "circt/Dialect/RTL/RTLOps.h"
#include "circt/Dialect/SV/SVDialect.h"
#include "circt/Dialect/SV/SVPasses.h"
#include "circt/Support/LoweringOptions.h"
#include "circt/Transforms/Passes.h"
#include "circt/Translation/ExportVerilog.h"
#include "mlir/Dialect/StandardOps/IR/Ops.h"
#include "mlir/IR/AsmState.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Parser.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/FileUtilities.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/ToolOutputFile.h"

using namespace llvm;
using namespace mlir;
using namespace circt;

/// Allow the user to specify the input file format.  This can be used to
/// override the input, and can be used to specify ambiguous cases like standard
/// input.
enum InputFormatKind { InputUnspecified, InputFIRFile, InputMLIRFile };

static cl::opt<InputFormatKind> inputFormat(
    "format", cl::desc("Specify input file format:"),
    cl::values(clEnumValN(InputUnspecified, "autodetect",
                          "Autodetect input format"),
               clEnumValN(InputFIRFile, "fir", "Parse as .fir file"),
               clEnumValN(InputMLIRFile, "mlir", "Parse as .mlir file")),
    cl::init(InputUnspecified));

static cl::opt<std::string>
    inputFilename(cl::Positional, cl::desc("<input file>"), cl::init("-"));

static cl::opt<std::string>
    outputFilename("o",
                   cl::desc("Output filename, or directory for split output"),
                   cl::value_desc("filename"), cl::init("-"));

static cl::opt<bool> disableOptimization("disable-opt",
                                         cl::desc("disable optimizations"));

static cl::opt<bool> lowerToRTL("lower-to-rtl",
                                cl::desc("run the lower-to-rtl pass"));
static cl::opt<bool> imconstprop(
    "imconstprop",
    cl::desc(
        "Enable intermodule constant propagation and dead code elimination"),
    cl::init(false));

static cl::opt<bool>
    enableLowerTypes("lower-types",
                     cl::desc("run the lower-types pass within lower-to-rtl"),
                     cl::init(false));

static cl::opt<bool>
    expandWhens("expand-whens", cl::desc("run the expand-whens pass on firrtl"),
                cl::init(false));

static cl::opt<bool>
    blackboxMemory("blackbox-memory",
                   cl::desc("Create a blackbox for all memory operations"),
                   cl::init(false));

static cl::opt<bool>
    ignoreFIRLocations("ignore-fir-locators",
                       cl::desc("ignore the @info locations in the .fir file"),
                       cl::init(false));

enum OutputFormatKind {
  OutputMLIR,
  OutputVerilog,
  OutputSplitVerilog,
  OutputDisabled
};

static cl::opt<OutputFormatKind> outputFormat(
    cl::desc("Specify output format:"),
    cl::values(clEnumValN(OutputMLIR, "mlir", "Emit MLIR dialect"),
               clEnumValN(OutputVerilog, "verilog", "Emit Verilog"),
               clEnumValN(OutputSplitVerilog, "split-verilog",
                          "Emit Verilog (one file per module; specify "
                          "directory with -o=<dir>)"),
               clEnumValN(OutputDisabled, "disable-output",
                          "Do not output anything")),
    cl::init(OutputMLIR));

static cl::opt<bool>
    verifyPasses("verify-each",
                 cl::desc("Run the verifier after each transformation pass"),
                 cl::init(true));

static cl::opt<std::string>
    inputAnnotationFilename("annotation-file",
                            cl::desc("Optional input annotation file"),
                            cl::value_desc("filename"));

/// Process a single buffer of the input.
static LogicalResult
processBuffer(std::unique_ptr<llvm::MemoryBuffer> ownedBuffer,
              StringRef annotationFilename,
              std::function<LogicalResult(OwningModuleRef)> callback) {
  MLIRContext context;

  // Register our dialects.
  context.loadDialect<firrtl::FIRRTLDialect, rtl::RTLDialect, comb::CombDialect,
                      sv::SVDialect>();

  llvm::SourceMgr sourceMgr;
  sourceMgr.AddNewSourceBuffer(std::move(ownedBuffer), llvm::SMLoc());
  SourceMgrDiagnosticHandler sourceMgrHandler(sourceMgr, &context);

  // Add the annotation file if one was explicitly specified.
  std::string annotationFilenameDetermined;
  if (!annotationFilename.empty()) {
    if (!(sourceMgr.AddIncludeFile(annotationFilename.str(), llvm::SMLoc(),
                                   annotationFilenameDetermined))) {
      llvm::errs() << "cannot open input annotation file '"
                   << annotationFilename << "': No such file or directory\n";
      return failure();
    }
  }

  // Nothing in the parser is threaded.  Disable synchronization overhead.
  auto isMultithreaded = context.isMultithreadingEnabled();
  context.disableMultithreading();

  // Apply any pass manager command line options.
  PassManager pm(&context);
  pm.enableVerifier(verifyPasses);
  applyPassManagerCLOptions(pm);

  OwningModuleRef module;
  if (inputFormat == InputFIRFile) {
    firrtl::FIRParserOptions options;
    options.ignoreInfoLocators = ignoreFIRLocations;
    module = importFIRRTL(sourceMgr, &context, options);

    if (enableLowerTypes) {
      pm.addNestedPass<firrtl::CircuitOp>(firrtl::createLowerFIRRTLTypesPass());
      auto &modulePM = pm.nest<firrtl::CircuitOp>().nest<firrtl::FModuleOp>();
      // Only enable expand whens if lower types is also enabled.
      if (expandWhens)
        modulePM.addPass(firrtl::createExpandWhensPass());
    }
    // If we parsed a FIRRTL file and have optimizations enabled, clean it up.
    if (!disableOptimization) {
      auto &modulePM = pm.nest<firrtl::CircuitOp>().nest<firrtl::FModuleOp>();
      modulePM.addPass(createCSEPass());
      modulePM.addPass(createSimpleCanonicalizerPass());
    }
  } else {
    assert(inputFormat == InputMLIRFile);
    module = parseSourceFile(sourceMgr, &context);

    if (enableLowerTypes) {
      pm.addNestedPass<firrtl::CircuitOp>(firrtl::createLowerFIRRTLTypesPass());
      auto &modulePM = pm.nest<firrtl::CircuitOp>().nest<firrtl::FModuleOp>();
      // Only enable expand whens if lower types is also enabled.
      if (expandWhens)
        modulePM.addPass(firrtl::createExpandWhensPass());
      // If we are running FIRRTL passes, clean up the output.
      if (!disableOptimization) {
        modulePM.addPass(createCSEPass());
        modulePM.addPass(createSimpleCanonicalizerPass());
      }
    }
  }
  if (!module)
    return failure();

  // Allow optimizations to run multithreaded.
  context.enableMultithreading(isMultithreaded);

  if (imconstprop)
    pm.nest<firrtl::CircuitOp>().addPass(firrtl::createIMConstPropPass());

  if (blackboxMemory)
    pm.nest<firrtl::CircuitOp>().addPass(firrtl::createBlackBoxMemoryPass());

  // Lower if we are going to verilog or if lowering was specifically requested.
  if (lowerToRTL || outputFormat == OutputVerilog ||
      outputFormat == OutputSplitVerilog) {
    pm.addPass(createLowerFIRRTLToRTLPass());
    pm.addPass(sv::createRTLMemSimImplPass());

    // If enabled, run the optimizer.
    if (!disableOptimization) {
      auto &modulePM = pm.nest<rtl::RTLModuleOp>();
      modulePM.addPass(sv::createRTLCleanupPass());
      modulePM.addPass(createCSEPass());
      modulePM.addPass(createSimpleCanonicalizerPass());
    }
  }

  // If we are going to verilog, sanitize the module names.
  if (outputFormat == OutputVerilog || outputFormat == OutputSplitVerilog) {
    pm.addPass(sv::createRTLLegalizeNamesPass());
  }

  // Load the emitter options from the command line. Command line options if
  // specified will override any module options.
  applyLoweringCLOptions(module.get());

  if (failed(pm.run(module.get())))
    return failure();

  return callback(std::move(module));
}

/// Process a single buffer of the input into a single output stream.
static LogicalResult
processBufferIntoSingleStream(std::unique_ptr<llvm::MemoryBuffer> ownedBuffer,
                              StringRef annotationFilename, raw_ostream &os) {
  return processBuffer(
      std::move(ownedBuffer), annotationFilename, [&](OwningModuleRef module) {
        // Finally, emit the output.
        switch (outputFormat) {
        case OutputMLIR:
          module->print(os);
          return success();
        case OutputDisabled:
          return success();
        case OutputVerilog:
          return exportVerilog(module.get(), os);
        case OutputSplitVerilog:
          llvm_unreachable("multi-file format must be handled elsewhere");
        }
        llvm_unreachable("unknown output format");
      });
}

/// Process a single buffer of the input into multiple output files.
static LogicalResult
processBufferIntoMultipleFiles(std::unique_ptr<llvm::MemoryBuffer> ownedBuffer,
                               StringRef annotationFilename,
                               StringRef outputDirectory) {
  return processBuffer(
      std::move(ownedBuffer), annotationFilename, [&](OwningModuleRef module) {
        // Finally, emit the output.
        switch (outputFormat) {
        case OutputMLIR:
        case OutputDisabled:
        case OutputVerilog:
          llvm_unreachable("single-stream format must be handled elsewhere");
        case OutputSplitVerilog:
          return exportSplitVerilog(module.get(), outputDirectory);
        }
        llvm_unreachable("unknown output format");
      });
}

int main(int argc, char **argv) {
  InitLLVM y(argc, argv);

  // Register any pass manager command line options.
  registerMLIRContextCLOptions();
  registerPassManagerCLOptions();
  registerAsmPrinterCLOptions();
  registerLoweringCLOptions();

  // Parse pass names in main to ensure static initialization completed.
  cl::ParseCommandLineOptions(argc, argv, "circt modular optimizer driver\n");

  // Figure out the input format if unspecified.
  if (inputFormat == InputUnspecified) {
    if (StringRef(inputFilename).endswith(".fir"))
      inputFormat = InputFIRFile;
    else if (StringRef(inputFilename).endswith(".mlir"))
      inputFormat = InputMLIRFile;
    else {
      llvm::errs() << "unknown input format: "
                      "specify with -format=fir or -format=mlir\n";
      exit(1);
    }
  }

  // Set up the input file.
  std::string errorMessage;
  auto input = openInputFile(inputFilename, &errorMessage);
  if (!input) {
    llvm::errs() << errorMessage << "\n";
    return 1;
  }

  // Emit a single file or multiple files depending on the output format.
  switch (outputFormat) {
  // Outputs into a single stream.
  case OutputMLIR:
  case OutputDisabled:
  case OutputVerilog: {
    auto output = openOutputFile(outputFilename, &errorMessage);
    if (!output) {
      llvm::errs() << errorMessage << "\n";
      return 1;
    }

    if (failed(processBufferIntoSingleStream(
            std::move(input), inputAnnotationFilename, output->os())))
      return 1;

    output->keep();
    return 0;
  }

  // Outputs into multiple files.
  case OutputSplitVerilog:
    if (outputFilename.isDefaultOption() || outputFilename == "-") {
      llvm::errs() << "missing output directory: specify with -o=<dir>\n";
      return 1;
    }
    std::error_code error = llvm::sys::fs::create_directory(outputFilename);
    if (error) {
      llvm::errs() << "cannot create output directory '" << outputFilename
                   << "': " << error.message() << "\n";
      return 1;
    }

    if (failed(processBufferIntoMultipleFiles(
            std::move(input), inputAnnotationFilename, outputFilename)))
      return 1;
    return 0;
  }
}
