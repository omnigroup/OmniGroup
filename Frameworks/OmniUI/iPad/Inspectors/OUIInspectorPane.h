// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIInspectorUpdateReason.h>

@class OUIInspector, OUIInspectorSlice;

@interface OUIInspectorPane : UIViewController

@property(readonly,nonatomic) BOOL inInspector;

/// There is a precondition in this getter that asserts that the ivar is non-null before returning it. There is no way to guarantee that this will not be nil because there is no initializer that requires it. For this NOT to crash, this pane first needs to be added to an OUIInspector so that it can set this property. Alternately, we could just remove the precondition.
@property(weak,nonatomic, nullable) OUIInspector *inspector; // Set by the containing inspector


@property(weak,nonatomic, nullable) OUIInspectorSlice *parentSlice; // Set by the parent slice, if any.

@property(nonatomic,copy, nullable) NSArray *inspectedObjects; // Typically should NOT be set by anything other than -pushPane: or -pushPane:inspectingObjects:.

// Allow panes to configure themselves before being pushed onto the OUIInspector's navigation controller. This is important since the navigation controller queries some properties before -viewWillAppear: is called.
- (void)inspectorWillShow:(nonnull OUIInspector *)inspector;

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;

@end

