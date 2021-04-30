// RUN: circt-opt --pass-pipeline='firrtl.circuit(firrtl.module(firrtl-expand-whens))' %s | FileCheck %s
firrtl.circuit "ExpandWhens" {
firrtl.module @ExpandWhens () {}

// Test that last connect semantics are resolved for connects.
firrtl.module @shadow_connects(%out : !firrtl.flip<uint<1>>) {
  %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
  %c1_ui1 = firrtl.constant(1 : ui1) : !firrtl.uint<1>
  firrtl.connect %out, %c0_ui1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
  firrtl.connect %out, %c1_ui1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
}
// CHECK-LABEL: firrtl.module @shadow_connects(%out: !firrtl.flip<uint<1>>) {
// CHECK-NEXT:   %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
// CHECK-NEXT:   %c1_ui1 = firrtl.constant(1 : ui1) : !firrtl.uint<1>
// CHECK-NEXT:   firrtl.connect %out, %c1_ui1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
// CHECK-NEXT: }


// Test that last connect semantics are resolved for partial connects.
firrtl.module @shadow_partialconnects(%out : !firrtl.flip<uint<1>>) {
  %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
  %c1_ui1 = firrtl.constant(1 : ui1) : !firrtl.uint<1>
  firrtl.partialconnect %out, %c0_ui1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
  firrtl.partialconnect %out, %c1_ui1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
}
// CHECK-LABEL: firrtl.module @shadow_partialconnects(%out: !firrtl.flip<uint<1>>) {
// CHECK-NEXT:   %c0_ui1 = firrtl.constant(0 : ui1) : !firrtl.uint<1>
// CHECK-NEXT:   %c1_ui1 = firrtl.constant(1 : ui1) : !firrtl.uint<1>
// CHECK-NEXT:   firrtl.partialconnect %out, %c1_ui1 : !firrtl.flip<uint<1>>, !firrtl.uint<1>
// CHECK-NEXT: }


// Test that last connect semantics are resolved in a WhenOp
firrtl.module @shadow_when(%p : !firrtl.uint<1>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  firrtl.when %p {
    %w = firrtl.wire : !firrtl.uint<2>
    firrtl.connect %w, %c0_ui2 : !firrtl.uint<2>, !firrtl.uint<2>
    firrtl.connect %w, %c1_ui2 : !firrtl.uint<2>, !firrtl.uint<2>
  }
}
// CHECK-LABEL: firrtl.module @shadow_when(%p: !firrtl.uint<1>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %w = firrtl.wire  : !firrtl.uint<2>
// CHECK-NEXT:   firrtl.connect %w, %c1_ui2 : !firrtl.uint<2>, !firrtl.uint<2>
// CHECK-NEXT: }


// Test all simulation constructs
firrtl.module @simulation(%clock : !firrtl.clock, %p : !firrtl.uint<1>, %enable : !firrtl.uint<1>, %reset : !firrtl.uint<1>) {
  firrtl.when %p {
    firrtl.printf %clock, %enable, "CIRCT Rocks!"
    firrtl.stop %clock, %enable, 0
    firrtl.assert %clock, %p, %enable, ""
    firrtl.assume %clock, %p, %enable, ""
    firrtl.cover %clock, %p, %enable, ""
  } else {
    firrtl.printf %clock, %reset, "CIRCT Rocks!"
    firrtl.stop %clock, %enable, 1
    firrtl.assert %clock, %p, %enable, ""
    firrtl.assume %clock, %p, %enable, ""
    firrtl.cover %clock, %p, %enable, ""
  }
}
// CHECK-LABEL: firrtl.module @simulation(%clock: !firrtl.clock, %p: !firrtl.uint<1>, %enable: !firrtl.uint<1>, %reset: !firrtl.uint<1>) {
// CHECK-NEXT:   %0 = firrtl.and %p, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.printf %clock, %0, "CIRCT Rocks!"
// CHECK-NEXT:   %1 = firrtl.and %p, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.stop %clock, %1, 0
// CHECK-NEXT:   %2 = firrtl.and %p, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.assert %clock, %p, %2, ""
// CHECK-NEXT:   %3 = firrtl.and %p, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.assume %clock, %p, %3, ""
// CHECK-NEXT:   %4 = firrtl.and %p, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.cover %clock, %p, %4, ""
// CHECK-NEXT:   %5 = firrtl.not %p : (!firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   %6 = firrtl.and %5, %reset : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.printf %clock, %6, "CIRCT Rocks!"
// CHECK-NEXT:   %7 = firrtl.and %5, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.stop %clock, %7, 1
// CHECK-NEXT:   %8 = firrtl.and %5, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.assert %clock, %p, %8, ""
// CHECK-NEXT:   %9 = firrtl.and %5, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.assume %clock, %p, %9, ""
// CHECK-NEXT:   %10 = firrtl.and %5, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.cover %clock, %p, %10, ""
// CHECK-NEXT: }


// Test nested when operations work correctly.
firrtl.module @nested_whens(%clock : !firrtl.clock, %p0 : !firrtl.uint<1>, %p1 : !firrtl.uint<1>, %enable : !firrtl.uint<1>, %reset : !firrtl.uint<1>) {
  firrtl.when %p0 {
    firrtl.when %p1 {
      firrtl.printf %clock, %enable, "CIRCT Rocks!"
    }
  }
}
// CHECK-LABEL: firrtl.module @nested_whens(%clock: !firrtl.clock, %p0: !firrtl.uint<1>, %p1: !firrtl.uint<1>, %enable: !firrtl.uint<1>, %reset: !firrtl.uint<1>) {
// CHECK-NEXT:   %0 = firrtl.and %p0, %p1 : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   %1 = firrtl.and %0, %enable : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.printf %clock, %1, "CIRCT Rocks!"
// CHECK-NEXT: }


// Test that a parameter set in both sides of the connect is resolved. The value
// used is local to each region.
firrtl.module @set_in_both(%clock : !firrtl.clock, %p : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  firrtl.when %p {
    %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
    firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  } else {
    %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
    firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  }
}
// CHECK-LABEL: firrtl.module @set_in_both(%clock: !firrtl.clock, %p: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %0 = firrtl.not %p : (!firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %1 = firrtl.mux(%p, %c0_ui2, %c1_ui2) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
// CHECK-NEXT:   firrtl.connect %out, %1 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
// CHECK-NEXT: }


// Test that a parameter set before a WhenOp, and then in both sides of the
// WhenOp is resolved.
firrtl.module @set_before_and_in_both(%clock : !firrtl.clock, %p : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  %c2_ui2 = firrtl.constant(2 : ui2) : !firrtl.uint<2>
  firrtl.connect %out, %c2_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  firrtl.when %p {
    firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  } else {
     firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  }
}
// CHECK-LABEL: firrtl.module @set_before_and_in_both(%clock: !firrtl.clock, %p: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c2_ui2 = firrtl.constant(2 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %0 = firrtl.not %p : (!firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   %1 = firrtl.mux(%p, %c0_ui2, %c1_ui2) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
// CHECK-NEXT:   firrtl.connect %out, %1 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
// CHECK-NEXT: } 


// Test that a parameter set in a WhenOp is not the last connect.
firrtl.module @set_after(%clock : !firrtl.clock, %p : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  %c2_ui2 = firrtl.constant(2 : ui2) : !firrtl.uint<2>
  firrtl.when %p {
    firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  } else {
    firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  }
  firrtl.connect %out, %c2_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
}
// CHECK-LABEL: firrtl.module @set_after(%clock: !firrtl.clock, %p: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c2_ui2 = firrtl.constant(2 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %0 = firrtl.not %p : (!firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   %1 = firrtl.mux(%p, %c0_ui2, %c1_ui2) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
// CHECK-NEXT:   firrtl.connect %out, %c2_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
// CHECK-NEXT: }


// Test that wire written to in only the thenblock is resolved.
firrtl.module @set_in_then0(%clock : !firrtl.clock, %p : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  firrtl.when %p {
    firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  }
}
// CHECK-LABEL: firrtl.module @set_in_then0(%clock: !firrtl.clock, %p: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %0 = firrtl.mux(%p, %c1_ui2, %c0_ui2) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
// CHECK-NEXT:   firrtl.connect %out, %0 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
// CHECK-NEXT: }


// Test that wire written to in only the then block is resolved.
firrtl.module @set_in_then1(%clock : !firrtl.clock, %p : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  firrtl.when %p {
    firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  }
  firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
}
// CHECK-LABEL: firrtl.module @set_in_then1(%clock: !firrtl.clock, %p: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
// CHECK-NEXT: }


// Test that wire written to in only the else is resolved.
firrtl.module @set_in_else0(%p : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  firrtl.when %p {
  } else {
    firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  }
}
// CHECK-LABEL: firrtl.module @set_in_else0(%p: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %0 = firrtl.not %p : (!firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   %1 = firrtl.mux(%p, %c0_ui2, %c1_ui2) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
// CHECK-NEXT:   firrtl.connect %out, %1 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
// CHECK-NEXT: }


// Test that wire written to in only the else block is resolved.
firrtl.module @set_in_else1(%clock : !firrtl.clock, %p : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  firrtl.when %p {
  } else {
    firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  }
  firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
}
// CHECK-LABEL: firrtl.module @set_in_else1(%clock: !firrtl.clock, %p: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %0 = firrtl.not %p : (!firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
// CHECK-NEXT: }

// Check that nested WhenOps work.
firrtl.module @nested(%clock : !firrtl.clock, %p0 : !firrtl.uint<1>, %p1 : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  %c2_ui2 = firrtl.constant(2 : ui2) : !firrtl.uint<2>

  firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
  firrtl.when %p0 {
    firrtl.when %p1 {
      firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
    }
  }
}
// CHECK-LABEL: firrtl.module @nested(%clock: !firrtl.clock, %p0: !firrtl.uint<1>, %p1: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
// CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %c2_ui2 = firrtl.constant(2 : ui2) : !firrtl.uint<2>
// CHECK-NEXT:   %0 = firrtl.and %p0, %p1 : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
// CHECK-NEXT:   %1 = firrtl.mux(%p0, %c1_ui2, %c0_ui2) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
// CHECK-NEXT:   firrtl.connect %out, %1 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
// CHECK-NEXT: }


// Check that nested WhenOps work.
firrtl.module @nested2(%clock : !firrtl.clock, %p0 : !firrtl.uint<1>, %p1 : !firrtl.uint<1>, %out : !firrtl.flip<uint<2>>) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
  %c2_ui2 = firrtl.constant(2 : ui2) : !firrtl.uint<2>
  %c3_ui2 = firrtl.constant(3 : ui2) : !firrtl.uint<2>

  firrtl.when %p0 {
    firrtl.when %p1 {
      firrtl.connect %out, %c0_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
    } else {
      firrtl.connect %out, %c1_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
    }
  } else {
    firrtl.when %p1 {
      firrtl.connect %out, %c2_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
    } else {
      firrtl.connect %out, %c3_ui2 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
    }
  }
}
//CHECK-LABEL: firrtl.module @nested2(%clock: !firrtl.clock, %p0: !firrtl.uint<1>, %p1: !firrtl.uint<1>, %out: !firrtl.flip<uint<2>>) {
//CHECK-NEXT:   %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
//CHECK-NEXT:   %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>
//CHECK-NEXT:   %c2_ui2 = firrtl.constant(2 : ui2) : !firrtl.uint<2>
//CHECK-NEXT:   %c3_ui2 = firrtl.constant(3 : ui2) : !firrtl.uint<2>
//CHECK-NEXT:   %0 = firrtl.and %p0, %p1 : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
//CHECK-NEXT:   %1 = firrtl.not %p1 : (!firrtl.uint<1>) -> !firrtl.uint<1>
//CHECK-NEXT:   %2 = firrtl.and %p0, %1 : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
//CHECK-NEXT:   %3 = firrtl.mux(%0, %c0_ui2, %c1_ui2) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
//CHECK-NEXT:   %4 = firrtl.not %p0 : (!firrtl.uint<1>) -> !firrtl.uint<1>
//CHECK-NEXT:   %5 = firrtl.and %4, %p1 : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
//CHECK-NEXT:   %6 = firrtl.not %p1 : (!firrtl.uint<1>) -> !firrtl.uint<1>
//CHECK-NEXT:   %7 = firrtl.and %4, %6 : (!firrtl.uint<1>, !firrtl.uint<1>) -> !firrtl.uint<1>
//CHECK-NEXT:   %8 = firrtl.mux(%5, %c2_ui2, %c3_ui2) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
//CHECK-NEXT:   %9 = firrtl.mux(%p0, %3, %8) : (!firrtl.uint<1>, !firrtl.uint<2>, !firrtl.uint<2>) -> !firrtl.uint<2>
//CHECK-NEXT:   firrtl.connect %out, %9 : !firrtl.flip<uint<2>>, !firrtl.uint<2>
//CHECK-NEXT: }

// Test that registers are multiplexed with themselves.
firrtl.module @register_mux(%p : !firrtl.uint<1>, %clock: !firrtl.clock) {
  %c0_ui2 = firrtl.constant(0 : ui2) : !firrtl.uint<2>
  %c1_ui2 = firrtl.constant(1 : ui2) : !firrtl.uint<2>

  // CHECK: %reg0 = firrtl.reg %clock
  // CHECK: firrtl.connect %reg0, %reg0
  %reg0 = firrtl.reg %clock : (!firrtl.clock) -> !firrtl.uint<2>

  // CHECK: %reg1 = firrtl.reg %clock
  // CHECK: firrtl.connect %reg1, %c0_ui2
  %reg1 = firrtl.reg %clock : (!firrtl.clock) -> !firrtl.uint<2>
  firrtl.connect %reg1, %c0_ui2 : !firrtl.uint<2>, !firrtl.uint<2>

  // CHECK: %reg2 = firrtl.reg %clock 
  // CHECK: [[MUX:%.+]] = firrtl.mux(%p, %c0_ui2, %reg2)
  // CHECK: firrtl.connect %reg2, [[MUX]]
  %reg2 = firrtl.reg %clock : (!firrtl.clock) -> !firrtl.uint<2>
  firrtl.when %p {
    firrtl.connect %reg2, %c0_ui2 : !firrtl.uint<2>, !firrtl.uint<2>
  }
  
  // CHECK: %reg3 = firrtl.reg %clock
  // CHECK: [[MUX:%.+]] = firrtl.mux(%p, %c0_ui2, %c1_ui2)
  // CHECK: firrtl.connect %reg3, [[MUX]]
  %reg3 = firrtl.reg %clock : (!firrtl.clock) -> !firrtl.uint<2>
  firrtl.when %p {
    firrtl.connect %reg3, %c0_ui2 : !firrtl.uint<2>, !firrtl.uint<2>
  } else {
    firrtl.connect %reg3, %c1_ui2 : !firrtl.uint<2>, !firrtl.uint<2>
  }
}

}