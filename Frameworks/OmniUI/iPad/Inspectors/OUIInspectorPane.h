// Copyright 2010-2014 The Omni Group. All rights reserved.
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
@property(weak,nonatomic) OUIInspector *inspector; // Set by the containing inspector
@property(weak,nonatomic) OUIInspectorSlice *parentSlice; // Set by the parent slice, if any.

@property(nonatomic,copy) NSArray *inspectedObjects; // Typically should NOT be set by anything other than -pushPane: or -pushPane:inspectingObjects:.

// Allow panes to configure themselves before being pushed onto the OUIInspector's navigation controller. This is important since the navigation controller queries some properties before -viewWillAppear: is called.
- (void)inspectorWillShow:(OUIInspector *)inspector;

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;

@end

