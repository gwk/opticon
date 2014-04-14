// Copyright 2014 George King.
// Permission to use this file is granted in opticon/license.txt (ISC).

// structs for packing multiple events into a single sqlite table.

#import "qk-types.h"


// TODO: fit up/down and moving bits in.
typedef struct {
  F64 time;
  I16 x : 16;
  I16 y : 16;
  U16 pressure : 16; // originally a double from 0 to 1. not very important, so ok to compress.
  U8 event_number: 8; // event number can be much larger than 256, but increments sequentially, so wrapped values are meaningful.
  U8 button_number: 2; // not clear what the technical maximum is, but 2 is the observed max.
  U8 click_state : 2; // single, double, or triple click.
  U8 subtype : 2; // CGEventMouseSubtype max value is 2.
  U8 down : 1; // boolean representing click-down and dragging.
  U8 moving : 1; // bolean representing move/drag.
} MouseEvent;


typedef struct {
  F64 time;
  U32 keycode;
  U32 keyboard_type : 31;
  U8 autorepeat : 1; // boolean.
  U8 down : 1; // boolean.
} KeyEvent;


typedef struct {
  F64 time;
  I32 delta1;
  I32 delta2;
} WheelEvent;
