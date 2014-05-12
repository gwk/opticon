#!/usr/bin/env python3
# Copyright 2014 George King.
# Permission to use this file is granted in license-opticon.txt (ISC license).

import os.path
import sqlite3
import struct
import sys

from datetime import datetime

event_type_names = [
  'Unknown',
  'DisabledByUser',
  'DisabledByTimeout',
  'Mouse',
  'Key',
  'Flags',
  'Wheel',
  'InputSourceChanged',
  'InputSourceQueried',
  'AppWillLaunch',
  'AppLaunched',
  'AppTerminated',
  'AppHid',
  'AppUnhid',
  'AppActivated',
  'AppDeactivated',
  'UserSessionActivated',
  'UserSessionDeactivated',
  'ActiveSpaceChanged',
  'SystemWillPowerOff',
  'SystemWoke',
  'SystemWillSleep',
  'SystemScreensSlept',
  'SystemScreensWoke',
]


mouse_struct  = struct.Struct('fhhHBB')
key_struct    = struct.Struct('fHHI')
wheel_struct  = struct.Struct('fii')

pressure_max = char_inv = (1<<16) - 1

if len(sys.argv) == 2:
  db_path = sys.argv[1]
else:
  db_path = os.path.expanduser('~/Documents/opticon.sqlite')
print('path:', db_path)

db = sqlite3.connect(db_path, detect_types=sqlite3.PARSE_DECLTYPES)

c = db.cursor()
c.execute('SELECT * FROM events')

for row in c:
  idx, time, type_id, pid, flags, data = row
  time_str = datetime.fromtimestamp(time)
  type_name = event_type_names[type_id]
  print('{:06} {} type:{:02} pid:{:05} flags:{:08X} {:16} '.format(idx, time_str, type_id, pid, flags, type_name), end='')
  if type_name == 'Mouse':
    print()
    for time, x, y, pressure_uns, event_num, bits in mouse_struct.iter_unpack(data):
      pressure = pressure_uns / pressure_max
      bttn  = (bits >> 0) & 0b11
      click = (bits >> 2) & 0b11
      sub   = (bits >> 4) & 0b11
      down  = (bits >> 6) & 0b1
      move  = (bits >> 7) & 0b1
      print('  t:{:.2f} x:{:+05} y:{:+05} pressure:{:.2} ev:{:03} bttn:{:01} click:{:01} sub:{:01} down:{:01} move:{:01}'.format(
        time, x, y, pressure, event_num, bttn, click, sub, down, move))
  elif type_name == 'Key':
    print()
    for time, code, char_ord, bits in key_struct.iter_unpack(data):
      kb    = (bits >> 0) & 0x3FFFFFFF
      ar    = (bits >> 30) & 0b1
      down  = (bits >> 31) & 0b1
      char = chr(char_ord)
      print('  t:{:.2f} code:{:02X} char:{} kb:{:02X} ar:{:01} down:{:01}'.format(time, code, repr(char), kb, ar, down))
  elif type_name == 'Wheel':
    print()
    for time, dx, dy in wheel_struct.iter_unpack(data):
      print('  t:{:.2f} dx:{:01} dy:{:01}'.format(time, dx, dy))
  elif data: # data column is utf8
    print(data.decode())
  else:
    print()
