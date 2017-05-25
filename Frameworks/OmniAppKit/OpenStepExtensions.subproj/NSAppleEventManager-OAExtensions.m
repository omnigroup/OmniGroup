// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSAppleEventManager-OAExtensions.h"

#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

static OSErr (*original_dispatchRawAppleEvent)(NSAppleEventManager* self, SEL _cmd, const AppleEvent *event, AppleEvent *reply, SRefCon handlerRefCon);

@implementation NSAppleEventManager (OAExtensions)

OBPerformPosing(^{
    Class self = objc_getClass("NSAppleEventManager");
    original_dispatchRawAppleEvent = (typeof(original_dispatchRawAppleEvent))OBReplaceMethodImplementation(self, @selector(dispatchRawAppleEvent:withRawReply:handlerRefCon:), (IMP)_replacement_dispatchRawAppleEvent);
});

static BOOL _aeListContainsObjectSpecifiers(const AEDescList *list)
{
    OSStatus status = noErr;
    long itemCount = 0;

    status = AECountItems(list, &itemCount);
    if (status != noErr) {
        return NO;
    }

    // N.B. AEDescLists are 1-based
    for (long i = 1; i <= itemCount; i++) {
        AEDesc itemDesc = {typeNull, NULL};
        
        status = AEGetNthDesc(list, i, typeWildCard, NULL, &itemDesc);
        if (status == noErr && itemDesc.descriptorType == typeObjectSpecifier) {
            AEDisposeDesc(&itemDesc);
            return YES;
        }
        
        AEDisposeDesc(&itemDesc);
    }
    
    return NO;
}

static BOOL _directParameterContainsObjectSpecifiers(const AppleEvent *event)
{
    OSStatus status = noErr;
    AEDesc descriptor = {typeNull, NULL};
    
    @try {
        status = AEGetParamDesc(event, keyDirectObject, typeWildCard, &descriptor);
        if (status != noErr) {
            return NO;
        }
        
        if (descriptor.descriptorType == typeObjectSpecifier) {
            return YES;
        }
        
        if (descriptor.descriptorType == typeAEList) {
            return _aeListContainsObjectSpecifiers((AEDescList *)&descriptor);
        }
    } @finally {
        AEDisposeDesc(&descriptor);
    }

    return NO;
}

static BOOL _shouldForceLazyInitializationOfSharedScriptSuiteRegistry(const AppleEvent *event)
{
    OSStatus status = noErr;
    DescType eventClass = 0;
    DescType eventID = 0;
    
    status = AEGetAttributePtr(event, keyEventClassAttr, typeType, NULL, &eventClass, sizeof(eventClass), NULL);
    if (status != noErr) {
        return NO;
    }

    status = AEGetAttributePtr(event, keyEventIDAttr, typeType, NULL, &eventID, sizeof(eventClass), NULL);
    if (status != noErr) {
        return NO;
    }

    if (eventClass == kCoreEventClass && eventID == kAEOpenDocuments) {
        if (_directParameterContainsObjectSpecifiers(event)) {
            return YES;
        }
    }
    
    return NO;
}

static OSErr _replacement_dispatchRawAppleEvent(NSAppleEventManager* self, SEL _cmd, const AppleEvent *event, AppleEvent *reply, SRefCon handlerRefCon)
{
    static BOOL hasForcedLazyInitializationOfSharedScriptSuiteRegistry = NO;
    
    // This is a workaround for <rdar://problem/7257705>.
    // Cocoa scripting initialization is too lazy, and things are not set up correctly for custom receivers of the 'open' command.
    // The symptom is that if your first interaction with the application is:
    //
    //    tell application "OmniFocus"
    //        open quick entry
    //    end tell
    //
    // that it just fails (without error on 10.6, with an error on 10.5). On 10.9.x, the event will eventually timeout.
    //
    // Any other event not in the required suite (even one implemented by a scripting addition) kicks things into the working state.
    //
    // Forcing the shared instance of the script suite registry to come into existance also works around the problem. But we don't want to do this unconditionally, because the scripting capabilities of any given application may depend on it's license type.
    //
    // So we force lazy initialization of the shared script suite registry for any 'odoc' event that has an object specifier in the direct parameter.
    
    if (!hasForcedLazyInitializationOfSharedScriptSuiteRegistry && _shouldForceLazyInitializationOfSharedScriptSuiteRegistry(event)) {
        hasForcedLazyInitializationOfSharedScriptSuiteRegistry = YES;
        (void)[NSScriptSuiteRegistry sharedScriptSuiteRegistry];
    }
    
    return original_dispatchRawAppleEvent(self, _cmd, event, reply, handlerRefCon);
}

@end
