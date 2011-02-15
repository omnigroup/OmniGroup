// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniUI/OUIColorValue.h>

@class OUIInspectorSelectionValue;

@protocol OUIColorInspectorPaneParentSlice <NSObject>
@property(readonly,nonatomic) OUIInspectorSelectionValue *selectionValue;
- (void)changeColor:(id <OUIColorValue>)colorValue;
@end
