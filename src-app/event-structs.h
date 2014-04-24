// Copyright 2014 George King.
// Permission to use this file is granted in opticon/license.txt (ISC).

// structs for packing multiple events into a single sqlite table.

#import "qk-types.h"
#import "qk-macros.h"


// TODO: fit up/down and moving bits in.
typedef struct {
  F64 time;
  I16 x;
  I16 y;
  U16 pressure; // originally a double from 0 to 1. not very important, so ok to compress.
  U8 event_num; // event number can be much larger than 256, but increments sequentially, so wrapped values are meaningful.
  U8 button: 2; // not clear what the technical maximum is, but 2 is the observed max.
  U8 clicks : 2; // single, double, or triple click.
  U8 subtype : 2; // CGEventMouseSubtype max value is 2.
  U8 down : 1; // boolean representing click-down and dragging.
  U8 moving : 1; // bolean representing move/drag.
} MouseEvent;


typedef struct {
  F64 time;
  U16 keycode;
  U16 character;
  U32 keyboard : 30;
  U32 autorepeat : 1; // boolean.
  U32 down : 1; // boolean.
} KeyEvent;


typedef struct {
  F64 time;
  I32 dx;
  I32 dy;
} WheelEvent;


static void assert_struct_types_are_valid() {
  qk_assert(sizeof(MouseEvent) == 16, @"bad struct size for MouseEvent.");
  qk_assert(sizeof(KeyEvent) == 16,   @"bad struct size for KeyEvent.");
  qk_assert(sizeof(WheelEvent) == 16, @"bad struct size for WheelEvent.");
}

