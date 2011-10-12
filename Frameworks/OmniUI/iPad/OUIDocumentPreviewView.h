// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@class OUIDocumentPreview;

@interface OUIDocumentPreviewView : UIView

@property(assign,nonatomic) BOOL group; // Must be YES if [previews count] > 1

@property(readonly,nonatomic) NSArray *previews;
- (void)addPreview:(OUIDocumentPreview *)preview;
- (void)discardPreviews;
- (CGRect)previewRectInFrame:(CGRect)frame;

@property(assign,nonatomic) BOOL selected;
@property(assign,nonatomic) BOOL draggingSource;

@property(assign,nonatomic) NSTimeInterval animationDuration;
@property(assign,nonatomic) UIViewAnimationCurve animationCurve;

@property(nonatomic,retain) UIImage *statusImage;
@property(nonatomic,assign) BOOL showsProgress;
@property(nonatomic,assign) double progress;

@end
