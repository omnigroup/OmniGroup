// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATextAttachment.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <OmniAppKit/OATextAttachmentCell.h>

@implementation OATextAttachment

- initWithFileWrapper:(NSFileWrapper *)fileWrapper;
{
    if (!(self = [super init]))
        return nil;
    _fileWrapper = [fileWrapper retain];
    return self;
}

- (void)dealloc;
{
    [_fileWrapper release];

    _cell.attachment = nil;
    [_cell release];
    
    [super dealloc];
}

@synthesize fileWrapper = _fileWrapper;
@synthesize attachmentCell = _cell;
- (void)setAttachmentCell:(id <OATextAttachmentCell>)cell;
{
    if (_cell == cell)
        return;
    [_cell release];
    _cell = [cell retain];
    cell.attachment = self;
}

@end
#endif

