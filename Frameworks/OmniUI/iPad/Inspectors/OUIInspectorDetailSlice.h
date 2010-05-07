// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@class OUIInspector, OUIInspectorSlice;

@interface OUIInspectorDetailSlice : UIViewController
{
@private
    OUIInspectorSlice *_nonretained_slice;
}

@property(assign,nonatomic) OUIInspectorSlice *slice; // Set by the owning inspector slice
@property(readonly) OUIInspector *inspector;

- (void)updateInterfaceFromInspectedObjects;

- (void)wasPushed; // ... it wasn't an accident!

@end
