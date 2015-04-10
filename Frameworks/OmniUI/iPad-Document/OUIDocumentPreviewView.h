// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class OUIDocumentPreview;

extern void OUIDocumentPreviewViewSetNormalBorder(UIView *view);
extern void OUIDocumentPreviewViewSetLightBorder(UIView *view);

@interface OUIDocumentPreviewView : UIView

@property(assign,nonatomic) BOOL draggingSource;
@property(assign,nonatomic) BOOL highlighted;

@property(retain,nonatomic) OUIDocumentPreview *preview;

@property(assign,nonatomic) BOOL downloadRequested;

@end
