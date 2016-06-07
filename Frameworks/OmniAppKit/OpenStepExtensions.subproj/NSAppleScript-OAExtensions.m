// Copyright 2002-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAppleScript-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSAppleEventDescriptor-OAExtensions.h>
#import <OmniAppKit/OAFontCache.h>

RCS_ID("$Id$");

@interface NSAppleScript (ApplePrivateMethods)
// Foundation
- _initWithData:(NSData *)data error:(NSDictionary **)errorInfo;
+ (ComponentInstance)_defaultScriptingComponent;
- (OSAID)_compiledScriptID;
@end
                    
@implementation NSAppleScript (OAExtensions)

- (id)initWithData:(NSData *)data error:(NSDictionary **)errorInfo;
{
    return [self _initWithData:data error:errorInfo];
}

- (NSData *)compiledData;
{
    AEDesc descriptor;
    OSAError error;

    error = OSAStore([[self class] _defaultScriptingComponent], [self _compiledScriptID], typeOSAGenericStorage, kOSAModeNull, &descriptor);
    if (error != noErr)
        return nil;
    
    NSAppleEventDescriptor *desc = [NSAppleEventDescriptor newDescriptorWithAEDescNoCopy:(&descriptor)];
    NSData *result = [desc data];

    return result;
}

@end
