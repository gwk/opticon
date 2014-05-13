// Copyright 2014 George King.
// Permission to use this file is granted in license-opticon.txt (ISC license).

// structs for packing multiple events into a single row in the events table.
// they are currently all 12 bytes wide, but could be different from each other.

#import "qk-types.h"
#import "qk-macros.h"


typedef struct {
  F32 time;
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
  F32 time;
  U16 keycode;
  U16 character;
  U32 keyboard : 30; // maximum value is unspecified; the only instance I have seen fits in one byte.
  U32 autorepeat : 1; // boolean.
  U32 down : 1; // boolean.
} KeyEvent;


typedef struct {
  F32 time;
  I32 dx;
  I32 dy;
} WheelEvent;


// to simplify buffer implementation, we currently assume all event types are the same size.
static const Int eventSize = sizeof(MouseEvent);

static void assert_struct_types_are_valid() {
  qk_assert(sizeof(MouseEvent) == 12, @"bad struct size for MouseEvent.");
  qk_assert(sizeof(KeyEvent) == 12,   @"bad struct size for KeyEvent.");
  qk_assert(sizeof(WheelEvent) == 12, @"bad struct size for WheelEvent.");
}

