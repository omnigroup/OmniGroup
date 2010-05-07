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

@class OUIInspector;

@interface OUIInspectorStack : UIViewController
{
@private
    OUIInspector *_nonretained_inspector;
    NSArray *_slices;
}

@property(assign,nonatomic) OUIInspector *inspector; // Set by the containing inspector
@property(nonatomic,copy) NSArray *slices; // Managed by the OUIInspector.slices.

- (void)layoutSlices;

- (void)updateInterfaceFromInspectedObjects;

@end

