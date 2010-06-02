// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@protocol OUIDocumentPreview;

@interface OUIDocumentProxyView : UIView
{
@private
    id <OUIDocumentPreview> _preview;
    BOOL _selected;
    UIView *_selectionGrayView;
    NSArray *_shadowEdgeViews;
}

+ (void)setPlaceholderPreviewImage:(UIImage *)placeholderPreviewImage;
+ (UIImage *)placeholderPreviewImage;

- (NSArray *)shadowEdgeViews;

@property(retain,nonatomic) id <OUIDocumentPreview> preview;
@property(assign,nonatomic) BOOL selected;

@end

@class OUIDocumentPDFPreview;
extern void OUIDocumentProxyDrawPreview(CGContextRef ctx, OUIDocumentPDFPreview *pdfPreview, CGRect bounds);
