// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
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

- initWithIdentifier:(NSString *)identifier
           imageName:(NSString  *)imageName
           predicate:(NSPredicate *)predicate
localizedFilterChooserButtonLabel:(NSString *)localizedFilterChooserButtonLabel
localizedFilterChooserShortButtonLabel:(NSString *)localizedFilterChooserShortButtonLabel
localizedMatchingObjectsDescription:(NSString *)localizedMatchingObjectsDescription;


@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSString *imageName;
@property(nonatomic,readonly) NSPredicate *predicate; // Suitable for use with ODSFilter

@property(nonatomic,readonly) NSString *localizedFilterChooserButtonLabel; /*! Like "Show stencils" */
@property(nonatomic,readonly) NSString *localizedFilterChooserShortButtonLabel; /*! Like "Stencils".  For compact horizontal size class. */
@property(nonatomic,readonly) NSString *localizedMatchingObjectsDescription; /*! Standalone name of the kind of things this filter shows (like "stencils") */

@end
