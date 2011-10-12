// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentPreviewLoadOperation.h"

#import <OmniUI/OUIDocumentPickerItemView.h>
#import <OmniUI/OUIDocumentPreview.h>
#import <OmniUI/OUIDocumentStoreFileItem.h>
#import <OmniUI/OUIDocument.h>

#import "OUIDocumentPickerItemView-Internal.h"

RCS_ID("$Id$");

@implementation OUIDocumentPreviewLoadOperation
{
    OUIDocumentPickerItemView *_view;
    Class _documentClass;
    OUIDocumentStoreFileItem *_fileItem;
    BOOL _landscape;
}

- initWithView:(OUIDocumentPickerItemView *)view documentClass:(Class)documentClass fileItem:(OUIDocumentStoreFileItem *)fileItem landscape:(BOOL)landscape;
{
    OBPRECONDITION(view);
    OBPRECONDITION(OBClassIsSubclassOfClass(documentClass, [OUIDocument class]));
    OBPRECONDITION(fileItem);
    OBPRECONDITION(fileItem.ready);
    
    if (!(self = [super init]))
        return nil;
    
    _view = [view retain];
    _documentClass = documentClass;
    _fileItem = [fileItem retain];
    _landscape = landscape;
    
    return self;
}

- (void)dealloc;
{
    [_view release];
    [_fileItem release];
    [super dealloc];
}

- (void)main;
{
    OBPRECONDITION(![NSThread isMainThread]);
    
    OUIDocumentPreview *preview = nil;
    NSError *error = nil;

    OMNI_POOL_START {
        preview = [[_documentClass loadPreviewForFileItem:_fileItem withLandscape:_landscape error:&error] retain];
    } OMNI_POOL_END;
        
#if 0 && defined(DEBUG)
    sleep(1);
#endif

    if (preview == nil) {
        NSLog(@"Unable to load preview from %@: %@", _fileItem.fileURL, [error toPropertyList]);

        UIImage *image = [[_fileItem class] placeholderPreviewImageForFileItem:_fileItem landscape:_landscape];
        if (image)
            preview = [[[OUIDocumentPreview alloc] initWithFileItem:_fileItem date:_fileItem.date image:image landscape:_landscape type:OUIDocumentPreviewTypePlaceholder] autorelease];
        else {
            OBASSERT_NOT_REACHED("No placeholder image");
            preview = nil;
        }
    }
    
    main_async(^{
        [_view previewLoadOperation:self loadedPreview:preview];
        [preview release];
    });
}

@end
