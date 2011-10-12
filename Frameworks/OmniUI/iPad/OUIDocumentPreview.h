// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OUIDocumentStoreFileItem;

typedef enum {
    OUIDocumentPreviewTypeRegular, // Actual image that is based on document contents
    OUIDocumentPreviewTypePlaceholder, // There was no preview, so this is just a placeholder and we should try to make a real preview
    OUIDocumentPreviewTypeEmpty, // There was a zero-byte preview file, possibly indicating a problem with a previous attempt to generate a preview, so we should not try to generate a new preview
} OUIDocumentPreviewType;

@interface OUIDocumentPreview : OFObject

- initWithFileItem:(OUIDocumentStoreFileItem *)fileItem date:(NSDate *)date image:(UIImage *)image landscape:(BOOL)landscape type:(OUIDocumentPreviewType)type;

@property(nonatomic,readonly) OUIDocumentStoreFileItem *fileItem;
@property(nonatomic,readonly) NSDate *date;
@property(nonatomic,readonly) UIImage *image;
@property(nonatomic,readonly) CGSize size; // just image.size

@property(nonatomic,assign) BOOL superseded;

@property(nonatomic,readonly,getter=isLandscape) BOOL landscape;
@property(nonatomic,readonly) OUIDocumentPreviewType type;

- (void)drawInRect:(CGRect)rect;

@end
