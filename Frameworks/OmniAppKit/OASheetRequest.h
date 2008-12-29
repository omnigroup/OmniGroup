// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSWindow;

@interface OASheetRequest : OFObject
{
    NSWindow *sheet;
    NSWindow *docWindow;
    id modalDelegate;
    SEL didEndSelector;
    void *contextInfo;
}

+ (OASheetRequest *)sheetRequestWithSheet:(NSWindow *)sheet modalForWindow:(NSWindow *)docWindow modalDelegate:(id)modalDelegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo;

- (NSWindow *)docWindow;
- (void)beginSheet;

@end
