// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspectorController-Internal.h>

@class OIAutolayoutInspectorHeaderView;

@interface OIAutoLayoutInspectorController : OIInspectorController

@property (nonatomic, assign) BOOL drawsHeaderSeparator;
@property (nonatomic, strong) IBOutlet OIAutolayoutInspectorHeaderView *headerView;

/// Call this instead of -inspectorDidResize: if the caller knows whether any resultant view changes should be animated.
- (void)inspectorDidResize:(OIInspector *)resizedInspector animateUpdates:(BOOL)animate;

@end
