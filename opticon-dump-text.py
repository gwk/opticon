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

db_path = sys.argv[1]
query_args = sys.argv[2:]
query_suffix = ' WHERE ' + ' '.join(query_args) if query_args else ''
query = 'SELECT * FROM events' + query_suffix

if not os.path.isfile(db_path):
  print('db does not exist at path:', repr(db_path), file=sys.stderr)
  sys.exit(1)

db = sqlite3.connect(db_path, detect_types=sqlite3.PARSE_DECLTYPES)

c = db.cursor()
try:
  c.execute(query)
except sqlite3.OperationalError as e:
  print('error for query:', query, file=sys.stderr)
  raise

for row in c:
  idx, time, type_id, pid, flags, data = row
  time_str = datetime.fromtimestamp(time)
  type_name = event_type_names[type_id]
  if type_name != 'Key':
    continue
  print('{:06} {} type:{:02} pid:{:05} flags:{:08X} {:16} '.format(idx, time_str, type_id, pid, flags, type_name), end='')
  chars = []
  for time, code, char_ord, bits in key_struct.iter_unpack(data):
    kb    = (bits >> 0) & 0x3FFFFFFF
    ar    = (bits >> 30) & 0b1
    down  = (bits >> 31) & 0b1
    if not down: continue
    char = chr(char_ord)
    chars.append(char)
  print(repr(''.join(chars)))
