// Copyright 2014 George King.
// Permission to use this file is granted in opticon/license.txt (ISC).


#import <CoreGraphics/CGEvent.h>
#import "qk-log.h"
#import "qk-sql-util.h"
#import "NSDate+QK.h"
#import "NSString+QK.h"
#import "QKStructArray.h"
#import "SqlDatabase.h"
#import "event-structs.h"
#import "AppDelegate.h"

#define DB_ALWAYS_RESETS 1

AppDelegate* appDelegate;


@interface AppDelegate ()

@property (nonatomic) SqlDatabase* db;
@property (nonatomic) SqlStatement* insertEventStatement;
@property (nonatomic) F64 pendingEventTime;
@property (nonatomic) Int pendingEventPid;
@property (nonatomic) CGEventType pendingEventType;
@property (nonatomic) QKStructArray* pendingEventData;

@end


@implementation AppDelegate


static NSTimeInterval startTime;

void calculateStartTime() {
  NSTimeInterval now = [NSDate posixTime];
  NSTimeInterval timeSinceStartup = GetCurrentEventTime();
  startTime = now - timeSinceStartup;
}


static inline NSTimeInterval timestampForEvent(CGEventRef event) {
  CGEventTimestamp t = CGEventGetTimestamp(event); // in nanoseconds since startup.
  NSTimeInterval timeSinceStart = (NSTimeInterval)t / 1000000000.0;
  return startTime + timeSinceStart;
}


CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* ctx) {
  F64 time = timestampForEvent(event);
  NSData* data = nil;
  switch (type) {
    case kCGEventNull:
    case kCGEventTabletPointer:
    case kCGEventTabletProximity:
      return NULL;
    case kCGEventFlagsChanged:
      break;
    case kCGEventMouseMoved:
    case kCGEventLeftMouseDragged:
    case kCGEventRightMouseDragged:
    case kCGEventOtherMouseDragged:
    case kCGEventLeftMouseDown:
    case kCGEventLeftMouseUp:
    case kCGEventRightMouseDown:
    case kCGEventRightMouseUp:
    case kCGEventOtherMouseDown:
    case kCGEventOtherMouseUp: {
      CGPoint loc = CGEventGetLocation(event);
      U16 pressure = CGEventGetDoubleValueField(event, kCGMouseEventPressure) * max_U16; // double value is between 0 and 1.
      MouseEvent me = {
        .time=time,
        .x=(I16)loc.x,
        .y=(I16)loc.y,
        .pressure=pressure,
        .event_number=(U8)CGEventGetIntegerValueField(event, kCGMouseEventNumber),
        .button_number=(U8)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber),
        .click_state=(U8)CGEventGetIntegerValueField(event, kCGMouseEventClickState),
        .subtype=(U8)CGEventGetIntegerValueField(event, kCGMouseEventClickState),
      };
      data = [NSData dataWithBytes:&me length:sizeof(me)];
      break;
    }
    case kCGEventKeyDown:
    case kCGEventKeyUp: {
      KeyEvent ke = {
        .time=time,
        .keycode=(U32)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode),
        .keyboard_type=(U32)CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType),
        .autorepeat=(U8)CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat),
      };
      data = [NSData dataWithBytes:&ke length:sizeof(ke)];
    }
    case kCGEventScrollWheel: {
      WheelEvent we = {
        .time=time,
        .delta1=(I32)CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1),
        .delta2=(I32)CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2),
      };
      data = [NSData dataWithBytes:&we length:sizeof(we)];
      break;
    }
  }
  auto delegate = (__bridge AppDelegate*)ctx;
  Int pid = CGEventGetIntegerValueField(event, kCGEventTargetUnixProcessID);
  [delegate logTime:time type:type pid:pid flags:CGEventGetFlags(event) data:data];
  return NULL;
}

NSString* const inputSourceName = (__bridge NSString*)kTISNotifySelectedKeyboardInputSourceChanged;

void inputSourceChangedCallback(CFNotificationCenterRef center,
                                void* observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef userInfo) {
  auto delegate = (__bridge AppDelegate*)observer;
  TISInputSourceRef inputSource = TISCopyCurrentKeyboardLayoutInputSource();
  auto inputId = (__bridge NSString*)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);
  LOG(inputId);
  [delegate logTime:[NSDate posixTime] typeName:inputSourceName pid:0 string:inputId];
}


- (void)logTime:(F64)time
           type:(Int)type
            pid:(Int)pid
          flags:(Int)flags
           data:(NSData*)data {
  
  auto s = _insertEventStatement;
  [s bindIndex:1 F64:time];
  [s bindIndex:2 Int:type];
  [s bindIndex:3 Int:pid];
  [s bindIndex:4 U64:flags];
  [s bindIndex:5 data:data];
  [s execute];
}


- (void)logTime:(F64)time typeName:(NSString*)name pid:(Int)pid string:(NSString*)string {
  Int type = [nonstandardEventTypes[name] intValue];
  [self logTime:time type:type pid:pid flags:0 data:string.asUtf8Data];
}


static auto nonstandardEventTypes =
  @{NSWorkspaceWillLaunchApplicationNotification:     @101,
    NSWorkspaceDidLaunchApplicationNotification:      @102,
    NSWorkspaceDidTerminateApplicationNotification:   @103,
    NSWorkspaceDidHideApplicationNotification:        @104,
    NSWorkspaceDidUnhideApplicationNotification:      @105,
    NSWorkspaceDidActivateApplicationNotification:    @106,
    NSWorkspaceDidDeactivateApplicationNotification:  @107,
    inputSourceName: @201,
    };


- (void)workspaceNote:(NSNotification*)note {
  // workspace notification callback.
  F64 time = [NSDate posixTime]; // get this as soon as possible, for accuracy (probably negligable).
  // CGEventType numbers are low (apparently bit positions); we create additional id numbers well past those.
  NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
  Int type = [nonstandardEventTypes[note.name] intValue];
  [self logTime:time type:type pid:app.processIdentifier flags:0 data:app.bundleIdentifier.asUtf8Data];
}


- (void)setupDb {
#if DEBUG
  auto dbPath = [@"~/Documents/opticon-debug.sqlite" stringByExpandingTildeInPath];
#else
  auto dbPath = [@"~/Documents/opticon.sqlite" stringByExpandingTildeInPath];
#endif
  
  _db = [SqlDatabase withPath:dbPath writeable:YES create:YES];
  qk_check(_db, @"no database: %@", dbPath);
#if DB_ALWAYS_RESETS
  [_db execute:@"DROP TABLE IF EXISTS events"];
#endif
  
  [_db execute:
   @"CREATE TABLE IF NOT EXISTS events ( "
   @"id INTEGER PRIMARY KEY, "      // 0
   @"time REAL, "                   // 1
   @"type INTEGER, "                // 2
   @"pid INTEGER, "                 // 3
   @"flags INTEGER, "               // 4
   @"data BLOB"                     // 5
   @")"];
  
  _insertEventStatement = [_db prepareInsert:5 table:@"events"];
}


- (void)addNote:(NSString*)name {
  auto wsnc = [[NSWorkspace sharedWorkspace] notificationCenter];
  [wsnc addObserver:self selector:@selector(workspaceNote:) name:name object:nil];
}


- (void)setupMonitors {
  
  [self addNote:NSWorkspaceWillLaunchApplicationNotification];
  [self addNote:NSWorkspaceDidLaunchApplicationNotification];
  [self addNote:NSWorkspaceDidTerminateApplicationNotification];
  [self addNote:NSWorkspaceDidHideApplicationNotification];
  [self addNote:NSWorkspaceDidUnhideApplicationNotification];
  [self addNote:NSWorkspaceDidActivateApplicationNotification];
  [self addNote:NSWorkspaceDidDeactivateApplicationNotification];
  
  auto dnc = CFNotificationCenterGetDistributedCenter();
  CFNotificationCenterAddObserver(dnc,
                                  (__bridge void*)self,
                                  inputSourceChangedCallback,
                                  kTISNotifySelectedKeyboardInputSourceChanged,
                                  NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);
  
  CGEventMask eventMask = 0
  | CGEventMaskBit(kCGEventLeftMouseDown)
  | CGEventMaskBit(kCGEventLeftMouseUp)
  | CGEventMaskBit(kCGEventRightMouseDown)
  | CGEventMaskBit(kCGEventRightMouseUp)
  | CGEventMaskBit(kCGEventMouseMoved)
  | CGEventMaskBit(kCGEventLeftMouseDragged)
  | CGEventMaskBit(kCGEventRightMouseDragged)
  | CGEventMaskBit(kCGEventKeyDown)
  | CGEventMaskBit(kCGEventKeyUp)
  | CGEventMaskBit(kCGEventFlagsChanged)
  | CGEventMaskBit(kCGEventScrollWheel)
  //| CGEventMaskBit(kCGEventTabletPointer)
  //| CGEventMaskBit(kCGEventTabletProximity)
  | CGEventMaskBit(kCGEventOtherMouseDown)
  | CGEventMaskBit(kCGEventOtherMouseUp)
  | CGEventMaskBit(kCGEventOtherMouseDragged)
  ;
  
  CFMachPortRef tap =
  CGEventTapCreate(kCGAnnotatedSessionEventTap, // tap events as they flow into applications (as late as possible).
                   kCGTailAppendEventTap, // insert tap after any existing filters.
                   kCGEventTapOptionListenOnly, // passive tap.
                   eventMask,
                   eventTapCallback,
                   (__bridge void*)self);
  
  NSLog(@"tap: %p; enabled: %d", tap, CGEventTapIsEnabled(tap));
  
  CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
  CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], source, kCFRunLoopCommonModes);
  CFRelease(source);
  
  // key down/up events are only delivered if the current process is running as root,
  // or the process has been approved as trusted for accessibility.
  // this is set in System Preferences -> Security and Privacy -> Privacy -> Accessibility.
  auto options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
  BOOL isTrusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
  NSLog(@"accessibility trusted: %d", isTrusted);
}



- (void)applicationDidFinishLaunching:(NSNotification*)note {
  calculateStartTime();
  [self setupDb];
  [self setupMonitors];
}


- (void)applicationWillTerminate:(NSNotification *)notification {
  _db = nil; // should finalize the db.
}


@end
