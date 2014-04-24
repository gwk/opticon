// Copyright 2014 George King.
// Permission to use this file is granted in opticon/license.txt (ISC).


#import <CoreGraphics/CGEvent.h>
#import "qk-log.h"
#import "qk-sql-util.h"
#import "NSDate+QK.h"
#import "NSString+QK.h"
#import "QKMutableStructArray.h"
#import "SqlDatabase.h"
#import "event-structs.h"
#import "AppDelegate.h"

#define DB_ALWAYS_RESETS DEBUG && 1

AppDelegate* appDelegate;

static NSString* const iconStringEnabled = @"⎊";
static NSString* const iconStringDisabled = @"⎉";

static NSString* const tooltipEnabled = @"Disable Opticon to avoid collecting sensitive event data.";
static NSString* const tooltipDisabled = @"Enable Opticon to collect event data.";

typedef enum {
  EventTypeUnknown = 0,
  EventTypeDisabledByUser,
  EventTypeDisabledByTimeout,
  EventTypeMouse,
  EventTypeKey,
  EventTypeFlags,
  EventTypeWheel,
  EventTypeAppWillLaunch,
  EventTypeAppLaunched,
  EventTypeAppTerminated,
  EventTypeAppHid,
  EventTypeAppUnhid,
  EventTypeAppActivated,
  EventTypeAppDeactivated,
  EventTypeInputSourceChanged,
  EventTypeInputSourceQueried,
} OpticonEventType;


@interface AppDelegate ()

@property (nonatomic) SqlDatabase* db;
@property (nonatomic) SqlStatement* insertEventStatement;
@property (nonatomic) F64 pendingTime;
@property (nonatomic) OpticonEventType pendingType;
@property (nonatomic) Int pendingPid;
@property (nonatomic) U64 pendingFlags;
@property (nonatomic) QKMutableStructArray* pendingEventData;
@property (nonatomic) BOOL isLoggingEnabled;
@property (nonatomic) NSStatusItem* statusItem;
@property (nonatomic) CFMachPortRef eventTap;
@property (nonatomic) NSAttributedString* iconAttrStrEnabled;
@property (nonatomic) NSAttributedString* iconAttrStrDisabled;

@end


@implementation AppDelegate


#pragma mark - NSApplicationDelegate


- (void)applicationDidFinishLaunching:(NSNotification*)note {
  assert_struct_types_are_valid();
  calculateStartTime();
  [self setupDb];
  [self setupStatusItem];
  [self logInputSource:EventTypeInputSourceQueried];
  [self setupMonitors];
  self.isLoggingEnabled = YES;
}


- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
  // TODO: explicitly remove NSStatusBar icon from the menu bar?
  return NSTerminateNow;
}



- (void)applicationWillTerminate:(NSNotification *)notification {
  [self flushEvents];
  [_db close];
}


#pragma mark - AppDelegate


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


static unichar unicharForKey(U16 keyCode, CGEventFlags flags, U32 keyboardType, BOOL down, BOOL autorepeat) {
  TISInputSourceRef inputSource = TISCopyCurrentKeyboardLayoutInputSource(); // TODO: store this to avoid lookup?
  CFDataRef layoutData = (CFDataRef)TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData);
  const UCKeyboardLayout* layout = (const UCKeyboardLayout*)CFDataGetBytePtr(layoutData);
  UInt16 action = (autorepeat ? kUCKeyActionAutoKey : (down ? kUCKeyActionDown : kUCKeyActionUp));
  const UniCharCount maxLen = 2; // max possible is 255; supposedly in practice output is usually limited to 4.
  UInt32 keysDown = 0;
  UniCharCount len = 0;
  UniChar chars[maxLen];
  
  // modifiers are undocumented as far as I can tell.
  // credit to @jollyjinx for the hint: "cmd=1,s=2,o=8,ctrl=16"
  // https://twitter.com/jollyjinx/status/8024830691
  U32 modifiers = 0;
  if (flags & kCGEventFlagMaskAlphaShift) modifiers |= 2; // is this correct? what is alpha shift?
  if (flags & kCGEventFlagMaskShift)      modifiers |= 2;
  if (flags & kCGEventFlagMaskControl)    modifiers |= 16;
  if (flags & kCGEventFlagMaskAlternate)  modifiers |= 8;
  if (flags & kCGEventFlagMaskCommand)    modifiers |= 1;

  UCKeyTranslate(layout,
                 keyCode,
                 action,
                 modifiers, // supposedly in EventRecord.modifiers format, which is a mac classic quicktime type.
                 keyboardType,
                 kUCKeyTranslateNoDeadKeysBit,
                 &keysDown,
                 maxLen,
                 &len,
                 chars);
  
  if (len != 1) return USHRT_MAX;
  return chars[0];
}


CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType cgEventType, CGEventRef event, void* ctx) {
  F64 time = timestampForEvent(event);
  OpticonEventType type = EventTypeUnknown;
  Int pid = CGEventGetIntegerValueField(event, kCGEventTargetUnixProcessID);
  U64 flags = CGEventGetFlags(event);
  void* ptr = NULL;
  I32 len = 0;
  U8 isMouseMoving = 0;
  switch (cgEventType) {
    case kCGEventNull:
    case kCGEventTabletPointer:
    case kCGEventTabletProximity:
      return NULL;
    case kCGEventTapDisabledByUserInput:  type = EventTypeDisabledByUser; break;
    case kCGEventTapDisabledByTimeout:    type = EventTypeDisabledByTimeout; break;
    case kCGEventFlagsChanged:            type = EventTypeFlags; break;

    case kCGEventMouseMoved:
    case kCGEventLeftMouseDragged:
    case kCGEventRightMouseDragged:
    case kCGEventOtherMouseDragged:
      isMouseMoving = 1;
    case kCGEventLeftMouseDown:
    case kCGEventLeftMouseUp:
    case kCGEventRightMouseDown:
    case kCGEventRightMouseUp:
    case kCGEventOtherMouseDown:
    case kCGEventOtherMouseUp: {
      type = EventTypeMouse;
      CGPoint loc = CGEventGetLocation(event);
      U16 pressure = CGEventGetDoubleValueField(event, kCGMouseEventPressure) * max_U16; // double value is between 0 and 1.
      U8 down = (cgEventType == kCGEventLeftMouseDown || cgEventType == kCGEventLeftMouseDragged ||
                 cgEventType == kCGEventRightMouseDown || cgEventType == kCGEventRightMouseDragged ||
                 cgEventType == kCGEventOtherMouseDown || cgEventType == kCGEventOtherMouseDragged);
      MouseEvent me = {
        .time=time,
        .x=(I16)loc.x,
        .y=(I16)loc.y,
        .pressure=pressure,
        .event_num=(U8)CGEventGetIntegerValueField(event, kCGMouseEventNumber),
        .button=(U8)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber),
        .clicks=(U8)CGEventGetIntegerValueField(event, kCGMouseEventClickState),
        .subtype=(U8)CGEventGetIntegerValueField(event, kCGMouseEventClickState),
        .down=down,
        .moving=isMouseMoving,
      };
      ptr = &me;
      len = sizeof(me);
      break;
    }
    case kCGEventKeyDown:
    case kCGEventKeyUp: {
      type = EventTypeKey;
      U16 keycode = (U16)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
      U32 keyboard = (U32)CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType);
      U8 autorepeat = (U8)CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat);
      U8 down = (cgEventType == kCGEventKeyDown);
      U16 character = unicharForKey(keycode, (U32)flags, keyboard, down, autorepeat);
      KeyEvent ke = {
        .time=time,
        .keycode=keycode,
        .character=character,
        .keyboard=keyboard,
        .autorepeat=autorepeat,
        .down=down,
      };
      ptr = &ke;
      len = sizeof(ke);
      break;
    }
    case kCGEventScrollWheel: {
      type = EventTypeWheel;
      WheelEvent we = {
        .time=time,
        .dx=(I32)CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1),
        .dy=(I32)CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2),
      };
      ptr = &we;
      len = sizeof(we);
      break;
    }
  }
  auto delegate = (__bridge AppDelegate*)ctx;
  [delegate logTime:time type:type pid:pid flags:flags ptr:ptr len:len];
  return NULL;
}


NSString* const inputSourceName = (__bridge NSString*)kTISNotifySelectedKeyboardInputSourceChanged;

void inputSourceChangedCallback(CFNotificationCenterRef center,
                                void* observer,
                                CFStringRef name,
                                const void *object,
                                CFDictionaryRef userInfo) {
  auto delegate = (__bridge AppDelegate*)observer;
  [delegate logInputSource:EventTypeInputSourceChanged];
}


- (void)logTime:(F64)time
           type:(OpticonEventType)type
            pid:(Int)pid
          flags:(U64)flags
           data:(NSData*)data {
  
  auto s = _insertEventStatement;
  [s bindIndex:1 F64:time];
  [s bindIndex:2 Int:type];
  [s bindIndex:3 Int:pid];
  [s bindIndex:4 U64:flags];
  [s bindIndex:5 data:data];
  [s execute];
}


- (void)flushEvents {
  if (_pendingEventData.length) {
    [self logTime:_pendingTime type:_pendingType pid:_pendingPid flags:_pendingFlags data:_pendingEventData.data];
    _pendingTime = 0;
    _pendingType = EventTypeUnknown;
    _pendingPid = 0;
    _pendingFlags = 0;
    [_pendingEventData resetWithElSize:0];
  }
}


- (void)logTime:(F64)time type:(OpticonEventType)type pid:(Int)pid flags:(U64)flags ptr:(void*)ptr len:(I32)len {
  if (type != _pendingType || pid != _pendingPid || flags != _pendingFlags) {
    [self flushEvents];
    _pendingTime = time;
    _pendingType = type;
    _pendingPid = pid;
    _pendingFlags = flags;
    [_pendingEventData resetWithElSize:len];
  }
  qk_assert(_pendingEventData.elSize == len, @"mismatched elSize: %d; len: %d", _pendingEventData.elSize, len);
  [_pendingEventData appendEl:ptr];
}


- (void)logTime:(F64)time type:(OpticonEventType)type pid:(Int)pid string:(NSString*)string {
  [self flushEvents];
  [self logTime:time type:type pid:pid flags:0 data:string.asUtf8Data];
}


- (void)logInputSource:(OpticonEventType)type {
  F64 time = [NSDate posixTime];
  TISInputSourceRef inputSource = TISCopyCurrentKeyboardLayoutInputSource();
  auto inputId = (__bridge NSString*)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);
  [self logTime:time type:type pid:0 string:inputId];
}


static auto noteEventTypes =
@{NSWorkspaceWillLaunchApplicationNotification:     @(EventTypeAppWillLaunch),
  NSWorkspaceDidLaunchApplicationNotification:      @(EventTypeAppLaunched),
  NSWorkspaceDidTerminateApplicationNotification:   @(EventTypeAppTerminated),
  NSWorkspaceDidHideApplicationNotification:        @(EventTypeAppHid),
  NSWorkspaceDidUnhideApplicationNotification:      @(EventTypeAppUnhid),
  NSWorkspaceDidActivateApplicationNotification:    @(EventTypeAppActivated),
  NSWorkspaceDidDeactivateApplicationNotification:  @(EventTypeAppDeactivated),
  };


- (void)workspaceNote:(NSNotification*)note {
  // workspace notification callback.
  F64 time = [NSDate posixTime]; // get this as soon as possible, for accuracy (probably negligable).
  // CGEventType numbers are low (apparently bit positions); we create additional id numbers well past those.
  NSRunningApplication* app = note.userInfo[NSWorkspaceApplicationKey];
  auto type = (OpticonEventType)[noteEventTypes[note.name] intValue];
  [self logTime:time type:type pid:app.processIdentifier string:app.bundleIdentifier];
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
  _pendingEventData = [QKMutableStructArray withElSize:0];
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
  
  _eventTap =
  CGEventTapCreate(kCGAnnotatedSessionEventTap, // tap events as they flow into applications (as late as possible).
                   kCGTailAppendEventTap, // insert tap after any existing filters.
                   kCGEventTapOptionListenOnly, // passive tap.
                   eventMask,
                   eventTapCallback,
                   (__bridge void*)self);
  
  //NSLog(@"tap: %p; enabled: %d", _eventTap, CGEventTapIsEnabled(_eventTap));
  CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, _eventTap, 0);
  CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], source, kCFRunLoopCommonModes);
  CFRelease(source);
  
  // key down/up events are only delivered if the current process is running as root,
  // or the process has been approved as trusted for accessibility.
  // this is set in System Preferences -> Security and Privacy -> Privacy -> Accessibility.
  auto options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
  BOOL isTrusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
  NSLog(@"accessibility trusted: %@", BIT_YN(isTrusted));
}


- (void)setIsLoggingEnabled:(BOOL)isLoggingEnabled {
  BOOL e = !!isLoggingEnabled;
  if (_isLoggingEnabled == e) return;
  NSLog(@"event logging enabled: %@", BIT_YN(e));
  _isLoggingEnabled = e;
  _statusItem.attributedTitle = e ? _iconAttrStrEnabled : _iconAttrStrDisabled;
  _statusItem.toolTip = e ? tooltipEnabled : tooltipDisabled;
  CGEventTapEnable(_eventTap, e);
}


- (void)toggleIsLoggingEnabled {
  self.isLoggingEnabled = !_isLoggingEnabled;
}


- (void)setupStatusItem {
  auto attrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:24]};
  _iconAttrStrEnabled = [[NSAttributedString alloc] initWithString:iconStringEnabled attributes:attrs];
  _iconAttrStrDisabled = [[NSAttributedString alloc] initWithString:iconStringDisabled attributes:attrs];

  NSStatusBar* statusBar = [NSStatusBar systemStatusBar];
  _statusItem = [statusBar statusItemWithLength:NSSquareStatusItemLength];
  _statusItem.highlightMode = YES;
  _statusItem.target = self;
  _statusItem.action = @selector(toggleIsLoggingEnabled);
}


@end
