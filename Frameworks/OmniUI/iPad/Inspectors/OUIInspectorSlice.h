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

@class OUIInspector, OUIInspectorPane;

@interface OUIInspectorSlice : UIViewController
{
@private
    OUIInspectorPane *_nonretained_containingPane;
    OUIInspectorPane *_detailPane;
}

@property(assign,nonatomic) OUIInspectorPane *containingPane; // Set by the containing inspector pane
@property(readonly,nonatomic) OUIInspector *inspector;

@property(retain,nonatomic) IBOutlet OUIInspectorPane *detailPane;
- (IBAction)showDetails:(id)sender;

- (BOOL)isAppropriateForInspectedObjects:(NSSet *)objects; // shouldn't be subclassed
@property(readonly) NSSet *appropriateObjectsForInspection; // filtered version of the inspector's inspectedObjects

- (BOOL)isAppropriateForInspectedObject:(id)object; // must be subclassed
- (void)updateInterfaceFromInspectedObjects; // should be subclassed

- (NSNumber *)singleSelectedValueForCGFloatSelector:(SEL)sel;
- (NSNumber *)singleSelectedValueForIntegerSelector:(SEL)sel;
- (NSValue *)singleSelectedValueForCGPointSelector:(SEL)sel;

@end
