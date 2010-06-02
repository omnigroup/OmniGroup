// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSArray, NSString;
@class OUIInspector;

@protocol OUIInspectorDelegate <NSObject>
- (NSString *)inspectorTitle:(OUIInspector *)inspector;
- (NSArray *)inspectorSlices:(OUIInspector *)inspector;

/* Delegates should normally implement this method to restore the first responder. */
- (void)inspectorDidDismiss:(OUIInspector *)inspector;

@end
