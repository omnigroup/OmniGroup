// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSelectionSet.h>

@protocol OIInspectableController;

@interface OIInspectionSet : OFSelectionSet

@property(nonatomic,copy) NSString *inspectionIdentifier;

// The OIInspectableController-conforming objects that were consulted when forming an inspection set.
@property(nonatomic,copy) NSArray <id <OIInspectableController>> *inspectableControllers;

@end
