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
#import <UIKit/UINibDeclarations.h>

@class OUIInspector, OUIInspectorDetailSlice;

@interface OUIInspectorSlice : UIViewController
{
@private
    OUIInspector *_nonretained_inspector;
    OUIInspectorDetailSlice *_detailSlice;
}

@property(assign,nonatomic) OUIInspector *inspector; // Set by the containing inspector

@property(retain,nonatomic) IBOutlet OUIInspectorDetailSlice *detailSlice;
- (IBAction)showDetails:(id)sender;

- (BOOL)isAppropriateForInspectedObjects:(NSSet *)objects; // shouldn't be subclassed
@property(readonly) NSSet *appropriateObjectsForInspection; // filtered version of the inspector's inspectedObjects

- (BOOL)isAppropriateForInspectedObject:(id)object; // must be subclassed
- (void)updateInterfaceFromInspectedObjects; // should be subclassed

- (NSNumber *)singleSelectedValueForCGFloatSelector:(SEL)sel;
- (NSNumber *)singleSelectedValueForIntegerSelector:(SEL)sel;
- (NSValue *)singleSelectedValueForCGPointSelector:(SEL)sel;

@end
