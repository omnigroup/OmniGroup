// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATextAttachment.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <OmniAppKit/OATextAttachmentCell.h>
#import <OmniFoundation/OFUTI.h>

@implementation OATextAttachment
{
    NSFileWrapper *_fileWrapper;
    id <OATextAttachmentCell> _cell;
}

- initWithFileWrapper:(NSFileWrapper *)fileWrapper;
{
    NSData *contents = nil;
    NSString *fileType = nil;

    if (fileWrapper) {
        OBASSERT([fileWrapper isRegularFile] || [fileWrapper isDirectory]);
        
        NSString *fileName = fileWrapper.filename;
        if (fileName == nil)
            fileName = fileWrapper.preferredFilename;
        if (fileName != nil)
            fileType = OFUTIForFileExtensionPreferringNative([fileName pathExtension], @([fileWrapper isDirectory]));
        
        if ([fileWrapper isRegularFile])
            contents = [fileWrapper regularFileContents];
    }
    
    if (!(self = [super initWithData:contents ofType:fileType]))
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
