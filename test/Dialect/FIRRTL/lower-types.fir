; RUN: circt-translate -import-firrtl %s -verify-diagnostics | circt-opt -pass-pipeline='firrtl.circuit(firrtl-lower-types)' | FileCheck %s
; XFAIL: *

circuit TypeCanonicalizationStillConsideredHarmful:
  module TypeCanonicalizationStillConsideredHarmful:

    ; This test checks that all legal connections involving a sink
    ; flow work.  In contrast to duplex flow, certain formulations
    ; will cause errors as opposed to reverse connections.  E.g., "d.a
    ; <- d.x", when involving a duplex flow would cause a connection
    ; flip, but is instead a connection error.  In this test,
    ; connections are explicitly flipped to be correct.  Erroneous
    ; connections are checked in lower-types-errors.fir.

    output a: {a:      {     a: UInt<1>}}
    output b: {a:      {flip a: UInt<1>}}
    output c: {flip a: {     a: UInt<1>}}
    output d: {flip a: {flip a: UInt<1>}}

    wire ax: {a:      {     a: UInt<1>}}
    wire bx: {a:      {flip a: UInt<1>}}
    wire cx: {flip a: {     a: UInt<1>}}
    wire dx: {flip a: {flip a: UInt<1>}}

    a <- ax
    a.a <- ax.a
    a.a.a <- ax.a.a
    ; CHECK:      firrtl.partialconnect %a_a_a, %ax_a_a
    ; CHECK-NEXT: firrtl.partialconnect %a_a_a, %ax_a_a
    ; CHECK-NEXT: firrtl.partialconnect %a_a_a, %ax_a_a

    a <= ax
    a.a <= ax.a
    a.a.a <= ax.a.a
    ; CHECK:      firrtl.connect %a_a_a, %ax_a_a
    ; CHECK-NEXT: firrtl.connect %a_a_a, %ax_a_a
    ; CHECK-NEXT: firrtl.connect %a_a_a, %ax_a_a

    b <- bx
    b.a <- bx.a
    bx.a.a <- b.a.a
    ; CHECK:      firrtl.partialconnect %bx_a_a, %b_a_a
    ; CHECK-NEXT: firrtl.partialconnect %bx_a_a, %b_a_a
    ; CHECK-NEXT: firrtl.partialconnect %bx_a_a, %b_a_a

    b <= bx
    b.a <= bx.a
    bx.a.a <= b.a.a
    ; CHECK:      firrtl.connect %bx_a_a, %b_a_a
    ; CHECK-NEXT: firrtl.connect %bx_a_a, %b_a_a
    ; CHECK-NEXT: firrtl.connect %bx_a_a, %b_a_a

    c <- cx
    cx.a <- c.a
    cx.a.a <- c.a.a
    ; CHECK:      firrtl.partialconnect %cx_a_a, %c_a_a
    ; CHECK-NEXT: firrtl.partialconnect %cx_a_a, %c_a_a
    ; CHECK-NEXT: firrtl.partialconnect %cx_a_a, %c_a_a

    c <= cx
    cx.a <= c.a
    cx.a.a <= c.a.a
    ; CHECK:      firrtl.connect %cx_a_a, %c_a_a
    ; CHECK-NEXT: firrtl.connect %cx_a_a, %c_a_a
    ; CHECK-NEXT: firrtl.connect %cx_a_a, %c_a_a

    d <- dx
    dx.a <- d.a
    d.a.a <- dx.a.a
    ; CHECK:      firrtl.partialconnect %d_a_a, %dx_a_a
    ; CHECK-NEXT: firrtl.partialconnect %d_a_a, %dx_a_a
    ; CHECK-NEXT: firrtl.partialconnect %d_a_a, %dx_a_a

    d <= dx
    dx.a <= d.a
    d.a.a <= dx.a.a
    ; CHECK:      firrtl.connect %d_a_a, %dx_a_a
    ; CHECK-NEXT: firrtl.connect %d_a_a, %dx_a_a
    ; CHECK-NEXT: firrtl.connect %d_a_a, %dx_a_a
