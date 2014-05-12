// Copyright 2014 George King.
// Permission to use this file is granted in license-opticon.txt (ISC license).

#import "event-structs.h"
#import "AppDelegate.h"


#if DEBUG
#define DBG_SUFFIX @" (debug)"
#else
#define DBG_SUFFIX @""
#endif

AppDelegate* appDelegate;

static NSString* const iconStringEnabled = @"⎊"; // U+238A CIRCLED TRIANGLE DOWN.
static NSString* const iconStringDisabled = @"⎉"; // U+2389 CIRCLED HORIZONTAL BAR WITH NOTCH.
static NSString* const iconStringError = @"○";// U+25CB WHITE CIRCLE

static NSString* const tooltipEnabled = @"Disable Opticon to avoid collecting sensitive event data." DBG_SUFFIX;
static NSString* const tooltipDisabled = @"Enable Opticon to collect event data." DBG_SUFFIX;
static NSString* const tooltipErrorFormat = @"Opticon encountered an error: %@" DBG_SUFFIX;


// these enumeration values are stored in the event table's 'type' column.
typedef enum {
  EventTypeUnknown = 0,
  EventTypeDisabledByUser,
  EventTypeDisabledByTimeout,
  EventTypeMouse,
  EventTypeKey,
  EventTypeFlags,
  EventTypeWheel,
  EventTypeInputSourceChanged,
  EventTypeInputSourceQueried,
  EventTypeAppWillLaunch,
  EventTypeAppLaunched,
  EventTypeAppTerminated,
  EventTypeAppHid,
  EventTypeAppUnhid,
  EventTypeAppActivated,
  EventTypeAppDeactivated,
  EventTypeUserSessionActivated,
  EventTypeUserSessionDeactivated,
  EventTypeActiveSpaceChanged,
  EventTypeSystemWillPowerOff,
  EventTypeSystemWoke,
  EventTypeSystemWillSleep,
  EventTypeSystemScreensSlept,
  EventTypeSystemScreensWoke,
} OpticonEventType;


@interface AppDelegate ()

@property (nonatomic) SqlDatabase* db;
@property (nonatomic) SqlStatement* insertEventStatement;

// fields for the pending event.
@property (nonatomic) F64 pendingTime;
@property (nonatomic) OpticonEventType pendingType;
@property (nonatomic) Int pendingPid;
@property (nonatomic) U64 pendingFlags;
@property (nonatomic) QKMutableStructArray* pendingEventData; // buffer of packed events to be stored in a single row.

@property (nonatomic) BOOL isLoggingEnabled;
@property (nonatomic) NSString* errorDesc;
@property (nonatomic) NSStatusItem* statusItem;
@property (nonatomic) CFMachPortRef eventTap;
@property (nonatomic) CFRunLoopSourceRef eventSource;
@property (nonatomic) NSAttributedString* iconAttrStrEnabled;
@property (nonatomic) NSAttributedString* iconAttrStrDisabled;
@property (nonatomic) NSAttributedString* iconAttrStrError;

@end


@implementation AppDelegate


#pragma mark - NSApplicationDelegate


- (void)applicationDidFinishLaunching:(NSNotification*)note {
  assert_struct_types_are_valid();
  calculateStartTime();
  _pendingEventData = [QKMutableStructArray withElSize:eventSize];
  [self setupDb];
  [self setupStatusItem];
  [self logInputSource:EventTypeInputSourceQueried];
  self.isLoggingEnabled = YES;
}


- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
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
  auto layoutData = (CFDataRef)TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData);
  auto layout = (const UCKeyboardLayout*)CFDataGetBytePtr(layoutData);
  UInt16 action = (autorepeat ? kUCKeyActionAutoKey : (down ? kUCKeyActionDown : kUCKeyActionUp));
  
  // max possible output length is 255; supposedly in practice output is usually limited to 4.
  // we get at most 2 characters, and then only store a char if we get back exactly one.
  // this way we can be certain that we are not truncating the output.
  const UniCharCount maxLen = 2;
  UInt32 keysDown = 0;
  UniCharCount len = 0;
  UniChar chars[maxLen];
  
  // modifiers are undocumented as far as I can tell.
  // credit to @jollyjinx for the hint: "cmd=1,s=2,o=8,ctrl=16"
  // https://twitter.com/jollyjinx/status/8024830691
  // i wonder what is the '4' bit for?
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


OpticonEventType eventTypeForCGType(CGEventType cgEventType) {
  switch (cgEventType) {
    case kCGEventNull:
    case kCGEventTabletPointer:
    case kCGEventTabletProximity:
      return EventTypeUnknown;
    case kCGEventTapDisabledByUserInput:
      return EventTypeDisabledByUser;
    case kCGEventTapDisabledByTimeout:
      return EventTypeDisabledByTimeout;
    case kCGEventFlagsChanged:
      return EventTypeFlags;
    case kCGEventMouseMoved:
    case kCGEventLeftMouseDragged:
    case kCGEventRightMouseDragged:
    case kCGEventOtherMouseDragged:
    case kCGEventLeftMouseDown:
    case kCGEventLeftMouseUp:
    case kCGEventRightMouseDown:
    case kCGEventRightMouseUp:
    case kCGEventOtherMouseDown:
    case kCGEventOtherMouseUp:
      return EventTypeMouse;
    case kCGEventKeyDown:
    case kCGEventKeyUp:
      return EventTypeKey;
    case kCGEventScrollWheel:
      return EventTypeWheel;
    default:
      return EventTypeUnknown;
  }
}


CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType cgEventType, CGEventRef event, void* ctx) {
  F64 time = timestampForEvent(event);
  OpticonEventType type = eventTypeForCGType(cgEventType);
  Int pid = CGEventGetIntegerValueField(event, kCGEventTargetUnixProcessID);
  U64 flags = CGEventGetFlags(event);
  auto delegate = (__bridge AppDelegate*)ctx;
  // flushing events inserts the previous pending event as a row in the database,
  // and sets the passed in data as the new pending event.
  F64 refTime = [delegate flushEventsForTime:time type:type pid:pid flags:flags];
  F32 relTime = time - refTime;
  void* ptr = NULL;
  switch (type) {
    case EventTypeDisabledByTimeout:
      delegate.errorDesc = @"Event tap timed out";
      return NULL;
    case EventTypeMouse: {
      CGPoint loc = CGEventGetLocation(event);
      U16 pressure = CGEventGetDoubleValueField(event, kCGMouseEventPressure) * max_U16; // double value is between 0 and 1.
      U8 down = (cgEventType == kCGEventLeftMouseDown || cgEventType == kCGEventLeftMouseDragged ||
                 cgEventType == kCGEventRightMouseDown || cgEventType == kCGEventRightMouseDragged ||
                 cgEventType == kCGEventOtherMouseDown || cgEventType == kCGEventOtherMouseDragged);
      U8 moving = (cgEventType &
                   (kCGEventMouseMoved |kCGEventLeftMouseDragged | kCGEventRightMouseDragged | kCGEventOtherMouseDragged));
      MouseEvent me = {
        .time=relTime,
        .x=(I16)loc.x,
        .y=(I16)loc.y,
        .pressure=pressure,
        .event_num=(U8)CGEventGetIntegerValueField(event, kCGMouseEventNumber),
        .button=(U8)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber),
        .clicks=(U8)CGEventGetIntegerValueField(event, kCGMouseEventClickState),
        .subtype=(U8)CGEventGetIntegerValueField(event, kCGMouseEventClickState),
        .down=down,
        .moving=moving,
      };
      ptr = &me;
      break;
    }
    case EventTypeKey: {
      U16 keycode = (U16)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
      U32 keyboard = (U32)CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType);
      U8 autorepeat = (U8)CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat);
      U8 down = (cgEventType == kCGEventKeyDown);
      U16 character = unicharForKey(keycode, (U32)flags, keyboard, down, autorepeat);
      KeyEvent ke = {
        .time=relTime,
        .keycode=keycode,
        .character=character,
        .keyboard=keyboard,
        .autorepeat=autorepeat,
        .down=down,
      };
      ptr = &ke;
      break;
    }
    case EventTypeWheel: {
      WheelEvent we = {
        .time=relTime,
        .dx=(I32)CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1),
        .dy=(I32)CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2),
      };
      ptr = &we;
      break;
    }
    default: return NULL;
  }
  [delegate appendEventDataPtr:ptr];
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


- (F64)flushEventsForTime:(F64)time type:(OpticonEventType)type pid:(Int)pid flags:(U64)flags {
  if (!time || !_pendingTime || type != _pendingType || pid != _pendingPid || flags != _pendingFlags) {
    if (_pendingEventData.length) {
      [self logTime:_pendingTime type:_pendingType pid:_pendingPid flags:_pendingFlags data:_pendingEventData.data];
    }
    _pendingTime = time;
    _pendingType = type;
    _pendingPid = pid;
    _pendingFlags = flags;
    [_pendingEventData clear];
  }
  return _pendingTime;
}


- (void)flushEvents {
  [self flushEventsForTime:0 type:EventTypeUnknown pid:0 flags:0];
}


- (void)appendEventDataPtr:(void*)ptr {
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
  NSWorkspaceSessionDidBecomeActiveNotification:    @(EventTypeUserSessionActivated),
  NSWorkspaceSessionDidResignActiveNotification:    @(EventTypeUserSessionDeactivated),
  NSWorkspaceActiveSpaceDidChangeNotification:      @(EventTypeActiveSpaceChanged),
  NSWorkspaceWillPowerOffNotification:              @(EventTypeSystemWillPowerOff),
  NSWorkspaceDidWakeNotification:                   @(EventTypeSystemWoke),
  NSWorkspaceWillSleepNotification:                 @(EventTypeSystemWillSleep),
  NSWorkspaceScreensDidSleepNotification:           @(EventTypeSystemScreensSlept),
  NSWorkspaceScreensDidWakeNotification:            @(EventTypeSystemScreensWoke),
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


- (void)observeNote:(NSString*)name {
  auto wsnc = [[NSWorkspace sharedWorkspace] notificationCenter];
  [wsnc addObserver:self selector:@selector(workspaceNote:) name:name object:nil];
}


- (void)setUpNotifications {
  auto dnc = CFNotificationCenterGetDistributedCenter();
  CFNotificationCenterAddObserver(dnc,
                                  (__bridge void*)self,
                                  inputSourceChangedCallback,
                                  kTISNotifySelectedKeyboardInputSourceChanged,
                                  NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);
  
  [self observeNote:NSWorkspaceWillLaunchApplicationNotification];
  [self observeNote:NSWorkspaceDidLaunchApplicationNotification];
  [self observeNote:NSWorkspaceDidTerminateApplicationNotification];
  [self observeNote:NSWorkspaceDidHideApplicationNotification];
  [self observeNote:NSWorkspaceDidUnhideApplicationNotification];
  [self observeNote:NSWorkspaceDidActivateApplicationNotification];
  [self observeNote:NSWorkspaceDidDeactivateApplicationNotification];
  [self observeNote:NSWorkspaceSessionDidBecomeActiveNotification];
  [self observeNote:NSWorkspaceSessionDidResignActiveNotification];
  [self observeNote:NSWorkspaceActiveSpaceDidChangeNotification];
  [self observeNote:NSWorkspaceWillPowerOffNotification];
  [self observeNote:NSWorkspaceDidWakeNotification];
  [self observeNote:NSWorkspaceWillSleepNotification];
  [self observeNote:NSWorkspaceScreensDidSleepNotification];
  [self observeNote:NSWorkspaceScreensDidWakeNotification];
}


- (void)tearDownNotifications {
  auto dnc = CFNotificationCenterGetDistributedCenter();
  CFNotificationCenterRemoveEveryObserver(dnc, (__bridge void*)self);
  [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self name:nil object:nil];
}


- (BOOL)checkIsTrusted {
  // key down/up events are only delivered if the current process is running as root,
  // or the process has been approved as trusted for accessibility.
  // TODO: since there does not seem to be a way to receive a notification if trust status is revoked,
  // we should periodically check that the process remains trusted; once a minute seems reasonable.
  auto options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
  BOOL isTrusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
  if (!isTrusted) {
    self.errorDesc = @"Opticon is not trusted; set trust in System Preferences -> Security and Privacy -> Privacy -> Accessibility";
    return NO;
  }
  return YES;
}

- (BOOL)setUpEventTap {
  if (![self checkIsTrusted]) return NO;
  
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
  
  _eventTap = CGEventTapCreate(kCGAnnotatedSessionEventTap, // tap events as they flow into applications (as late as possible).
                               kCGTailAppendEventTap, // insert tap after any existing filters.
                               kCGEventTapOptionListenOnly, // passive tap.
                               eventMask,
                               eventTapCallback,
                               (__bridge void*)self);
  if (!_eventTap) {
    self.errorDesc = @"failed to create event tap";
    return NO;
  }
  
  //NSLog(@"tap: %p; enabled: %d", _eventTap, CGEventTapIsEnabled(_eventTap));
  _eventSource = CFMachPortCreateRunLoopSource(NULL, _eventTap, 0);
  CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], _eventSource, kCFRunLoopCommonModes);
  return YES;
}


- (void)tearDownEventTap {
  if (_eventSource) {
    CFRunLoopRemoveSource([[NSRunLoop currentRunLoop] getCFRunLoop], _eventSource, kCFRunLoopCommonModes);
    CFRelease(_eventSource);
    _eventSource = NULL;
  }
  if (_eventTap) {
    CFRelease(_eventTap);
    _eventTap = NULL;
  }
}


- (void)setIsLoggingEnabled:(BOOL)isLoggingEnabled {
  BOOL e = !!isLoggingEnabled;
  if (_isLoggingEnabled == e) return;
  NSLog(@"event logging enabled: %@", BIT_YN(e));
  _isLoggingEnabled = e;
  _statusItem.attributedTitle = e ? _iconAttrStrEnabled : _iconAttrStrDisabled;
  //CGEventTapEnable(_eventTap, e); // rather than enable/disable, we do complete setup/teardown to reduce possible states.
  if (e) {
    [self setUpNotifications];
    [self setUpEventTap];
  } else {
    [self tearDownNotifications];
    [self tearDownEventTap];
  }
  [self updateStatusItem];
}


- (void)setErrorDesc:(NSString *)errorDesc {
  _errorDesc = errorDesc;
  NSLog(@"error: %@.", errorDesc);
  [self updateStatusItem];
}


- (void)toggleIsLoggingEnabled {
  _errorDesc = nil; // updateStatusItem will follow, so call to setter would be redundant.
  self.isLoggingEnabled = !_isLoggingEnabled;
}


- (void)setupStatusItem {
  auto attrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:24]};
  auto errorAttrs = @{NSFontAttributeName : [NSFont boldSystemFontOfSize:24],
                      NSForegroundColorAttributeName : [CUIColor r:.5]};
  _iconAttrStrEnabled   = [[NSAttributedString alloc] initWithString:iconStringEnabled attributes:attrs];
  _iconAttrStrDisabled  = [[NSAttributedString alloc] initWithString:iconStringDisabled attributes:attrs];
  _iconAttrStrError     = [[NSAttributedString alloc] initWithString:iconStringError attributes:errorAttrs];
  NSStatusBar* statusBar = [NSStatusBar systemStatusBar];
  _statusItem = [statusBar statusItemWithLength:NSSquareStatusItemLength];
  _statusItem.highlightMode = YES;
  _statusItem.target = self;
  _statusItem.action = @selector(toggleIsLoggingEnabled);
}


- (void)updateStatusItem {
  if (_errorDesc) {
    _statusItem.attributedTitle = _iconAttrStrError;
    _statusItem.toolTip = [NSString stringWithFormat:tooltipErrorFormat, _errorDesc];
  } else if (_isLoggingEnabled) {
    _statusItem.attributedTitle = _iconAttrStrEnabled;
    _statusItem.toolTip = tooltipEnabled;
  } else {
    _statusItem.attributedTitle = _iconAttrStrDisabled;
    _statusItem.toolTip = tooltipDisabled;
  }
}


@end
