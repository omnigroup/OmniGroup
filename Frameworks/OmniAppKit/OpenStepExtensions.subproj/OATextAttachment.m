// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OATextAttachment.h>

@import Foundation;
@import OmniBase;

#if OMNI_BUILDING_FOR_IOS
#import <OmniAppKit/OATextAttachmentCell.h>
#endif


RCS_ID("$Id$");

#if OMNI_BUILDING_FOR_IOS || OMNI_BUILDING_FOR_SERVER

#import <OmniFoundation/OFUTI.h>

@implementation OATextAttachment
{
    NSFileWrapper *_fileWrapper;
#if OMNI_BUILDING_FOR_IOS
    id <OATextAttachmentCell> _cell;
#endif
}

- initWithFileWrapper:(NSFileWrapper *)fileWrapper;
{
#if OMNI_BUILDING_FOR_IOS
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
#endif
    
    _fileWrapper = [fileWrapper retain];
    
    return self;
}

- (void)dealloc;
{
    [_fileWrapper release];

#if OMNI_BUILDING_FOR_IOS
    _cell.attachment = nil;
    [_cell release];
#endif

    [super dealloc];
}

@synthesize fileWrapper = _fileWrapper;

#if OMNI_BUILDING_FOR_IOS
@synthesize attachmentCell = _cell;
- (void)setAttachmentCell:(id <OATextAttachmentCell>)cell;
{
    if (_cell == cell)
        return;
    [_cell release];
    _cell = [cell retain];
    cell.attachment = self;
}
#endif

@end
#endif
