// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <OmniUI/OUIDocumentPreview.h>

@interface OUIDocumentPDFPreview : OFObject <OUIDocumentPreview>
{
@private
    CGPDFDocumentRef _document;
    CGPDFPageRef _page;
    CGRect _rect;
    
    CGSize _originalViewSize; // Just used to validate whether this preview is still good.
    UIImage *_cachedImage;
}

- initWithData:(NSData *)pdfData originalViewSize:(CGSize)originalViewSize;

- (void)drawInTransformedContext:(CGContextRef)ctx; // cxt should already have the appropriate transform set up.
- (void)cacheImageOfSize:(CGSize)size;

@end
