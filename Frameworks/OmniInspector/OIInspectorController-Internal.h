// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspectorController.h>


@interface OIInspectorController ()

// OIAutoLayoutInspectorController pokes this directly
@property(nonatomic,readwrite) BOOL isExpanded;

- (IBAction)toggleVisibleAction:(id)sender;

/**
 Called for embedded inspector controllers when the container view needs to be populated with a header and its inspector's content view. The default implementation uses an OIInspectorHeaderView (borrowed from the floating inspectors) and the inspector's inspectorView, if one is available.
 
 Override to customize the appearance of the header, the layout of the container, or both. Your implementation should not call super, but instead should completely replace the superclass's implementation with your own.
 */
- (void)populateContainerView;
@end
