// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OASheetRequest.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@interface OASheetRequest (Private)
- (id)_initWithSheet:(NSWindow *)aSheet modalForWindow:(NSWindow *)aDocWindow modalDelegate:(id)aModalDelegate didEndSelector:(SEL)aDidEndSelector contextInfo:(void *)aContextInfo;
@end

@implementation OASheetRequest

+ (OASheetRequest *)sheetRequestWithSheet:(NSWindow *)aSheet modalForWindow:(NSWindow *)aDocWindow modalDelegate:(id)aModalDelegate didEndSelector:(SEL)aDidEndSelector contextInfo:(void *)aContextInfo;
{
    return [[[OASheetRequest alloc] _initWithSheet:aSheet modalForWindow:aDocWindow modalDelegate:aModalDelegate didEndSelector:aDidEndSelector contextInfo:aContextInfo] autorelease];
}

- (void)dealloc;
{
    [sheet release];
    [docWindow release];
    [modalDelegate release];
    
    [super dealloc];
}

//
// API
//

- (NSWindow *)docWindow;
{
    return docWindow;
}

- (void)beginSheet;
{
    [NSApp beginSheet:sheet modalForWindow:docWindow modalDelegate:modalDelegate didEndSelector:didEndSelector contextInfo:contextInfo];
}

@end

@implementation OASheetRequest (NotificationsDelegatesDatasources)
@end

@implementation OASheetRequest (Private)

- (id)_initWithSheet:(NSWindow *)aSheet modalForWindow:(NSWindow *)aDocWindow modalDelegate:(id)aModalDelegate didEndSelector:(SEL)aDidEndSelector contextInfo:(void *)aContextInfo;
{
    if ([super init] == nil)
        return nil;
        
    sheet = [aSheet retain];
    docWindow = [aDocWindow retain];
    modalDelegate = [aModalDelegate retain];
    didEndSelector = aDidEndSelector;
    contextInfo = aContextInfo;
    
    return self;
}

@end
