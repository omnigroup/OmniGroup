// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <OmniUI/OUIColorValue.h>

@class OUIInspectorSelectionValue;
@class OAColor;

@protocol OUIColorInspectorPaneParentSlice <NSObject>

// If set, detail slices or subclasses may include a 'no color' option of some sort.
@property(nonatomic,assign) BOOL allowsNone;

// If allowsNone is YES, then this should also be implemented to return non-nil to get the color to use when switching away from nil.
@property(nonatomic,copy) OAColor *defaultColor;

@property(readonly,nonatomic) OUIInspectorSelectionValue *selectionValue;

- (void)changeColor:(id <OUIColorValue>)colorValue;

@end
