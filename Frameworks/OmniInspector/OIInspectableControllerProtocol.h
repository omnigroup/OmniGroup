// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OIInspectionSet;

@protocol OIInspectableController <NSObject>

- (void)addInspectedObjects:(OIInspectionSet *)inspectionSet;
/*" OIInspectorRegistry calls this on objects in the responder chain to collect the set of objects to inspect. "*/

@optional
- (NSString *)inspectionIdentifierForInspectionSet:(OIInspectionSet *)inspectionSet;

@end
