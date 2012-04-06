// Copyright 2010-2012 The Omni Group. All rights reserved.
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

@property(assign,nonatomic) BOOL landscape; // Can be derived if we have any previews, but not if we are just starting up
@property(assign,nonatomic) BOOL group; // Must be YES if [previews count] > 1
@property(assign,nonatomic) BOOL needsAntialiasingBorder;
@property(assign,nonatomic) BOOL selected;
@property(assign,nonatomic) BOOL draggingSource;
@property(assign,nonatomic) BOOL highlighted;

@property(readonly,nonatomic) NSArray *previews;
- (void)addPreview:(OUIDocumentPreview *)preview;
- (void)discardPreviews;

// Given a candidate frame, return the frame that should be used for the preview view
- (CGRect)previewRectInFrame:(CGRect)frame;

// Like -previewRectInFrame:, but this version will return a frame that is about the same sized as the input, not about the same size as the preview (with the preview scale applied).
- (CGRect)fitPreviewRectInFrame:(CGRect)frame;

// Returns the subrect of the recevier that will be covered by its preview (probably only useful for group==NO).
@property(readonly,nonatomic) CGRect imageBounds;


@property(assign,nonatomic) NSTimeInterval animationDuration;
@property(assign,nonatomic) UIViewAnimationCurve animationCurve;

@property(nonatomic,retain) UIImage *statusImage;
@property(assign,nonatomic) BOOL downloadRequested;
@property(assign,nonatomic) BOOL downloading;
@property(nonatomic,assign) BOOL showsProgress;
@property(nonatomic,assign) double progress;

@end
