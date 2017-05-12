// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniInspector/OIInspector.h>

@interface OIStackedSlicesInspector : OIInspector <OIConcreteInspector>

- (OIInspector <OIConcreteInspector> *)inspectorWithIdentifier:(NSString *)identifier;
- (NSArray <OIInspector *> *)sliceInspectors;

@end
