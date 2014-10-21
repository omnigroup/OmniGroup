// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

extern NSString * const ODSDocumentPickerFilterDocumentIdentifier;
extern NSString * const ODSDocumentPickerFilterTemplateIdentifier;


@interface OUIDocumentPickerFilter : NSObject

@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,copy) NSString *imageName;
@property(nonatomic,copy) NSPredicate *predicate; // Suitable for use with ODSFilter

@property(nonatomic,copy) NSString *localizedFilterChooserButtonLabel; /*! Like "Show stencils" */
@property(nonatomic,copy) NSString *localizedFilterChooserShortButtonLabel; /*! Like "Stencils".  For compact horizontal size class. */
@property(nonatomic,copy) NSString *localizedMatchingObjectsDescription; /*! Standalone name of the kind of things this filter shows (like "stencils") */

@end
