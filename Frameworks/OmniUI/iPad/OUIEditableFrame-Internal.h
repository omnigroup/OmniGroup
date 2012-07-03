// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIEditableFrame.h>

@interface OUIEditableFrame ()

/* These are the interface from the thumbs to our selection machinery */
- (void)thumbTapped:(OUITextThumb *)thumb recognizer:(UITapGestureRecognizer *)recognizer;
- (void)thumbTouchBegan:(OUITextThumb *)thumb;
- (void)thumbTouchEnded:(OUITextThumb *)thumb;
- (void)thumbDragBegan:(OUITextThumb *)thumb;
- (void)thumbDragMoved:(OUITextThumb *)thumb targetPosition:(CGPoint)pt;
- (void)thumbDragEnded:(OUITextThumb *)thumb normally:(BOOL)normalEnd;

@end
