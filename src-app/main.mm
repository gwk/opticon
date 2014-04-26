// Copyright 2014 George King.
// Permission to use this file is granted in license-opticon.txt (ISC license).


#import "NSApplication+QK.h"
#import "AppDelegate.h"


int main(int argc, const char * argv[]) {
  return [NSApplication launchWithDelegateClass:[AppDelegate class] activationPolicy:NSApplicationActivationPolicyAccessory];
}
