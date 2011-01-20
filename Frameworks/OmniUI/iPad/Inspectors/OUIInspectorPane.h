// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <UIKit/UIViewController.h>

@class OUIInspector, OUIInspectorSlice;

@interface OUIInspectorPane : UIViewController
{
@private
    OUIInspector *_nonretained_inspector; // the main inspector
    OUIInspectorSlice *_nonretained_parentSlice; // our parent slice if any
    NSSet *_inspectedObjects;
}

@property(assign,nonatomic) OUIInspector *inspector; // Set by the containing inspector
@property(assign,nonatomic) OUIInspectorSlice *parentSlice; // Set by the parent slice, if any.

@property(nonatomic,copy) NSSet *inspectedObjects; // Typically should NOT be set by anything other than -pushPane: or -pushPane:inspectingObjects:.


- (void)updateInterfaceFromInspectedObjects;

@end

