// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OQColor;

@protocol OUIColorValue <NSObject>
@property(readonly,nonatomic) OQColor *color;
@property(readonly,nonatomic) BOOL isContinuousColorChange;
@end

// Not implemented, but color editing controls send this up the responder chain.
@interface NSObject (OUIColorValue)
- (void)changeColor:(id <OUIColorValue>)colorValue;
@end
