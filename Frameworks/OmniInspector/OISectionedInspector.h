// Copyright 2007,2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OIInspector.h"

//@class NSAttributedString, NSMutableArray; // Foundation
//@class NSMatrix; // AppKit
//@class OIInspectorController;

#import <AppKit/NSNibDeclarations.h> // For IBOutlet and IBAction

@interface OISectionedInspector : OIInspector <OIConcreteInspector> 
{
    IBOutlet NSView *inspectionView;
    
    NSArray *_sectionInspectors;
    OIInspectorController *_nonretained_inspectorController;
}

@end
