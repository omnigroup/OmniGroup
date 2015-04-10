// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerFilter.h>

RCS_ID("$Id$");

NSString * const ODSDocumentPickerFilterDocumentIdentifier = @"document";
NSString * const ODSDocumentPickerFilterTemplateIdentifier = @"template";

@implementation OUIDocumentPickerFilter

- initWithIdentifier:(NSString *)identifier
           imageName:(NSString  *)imageName
           predicate:(NSPredicate *)predicate
localizedFilterChooserButtonLabel:(NSString *)localizedFilterChooserButtonLabel
localizedFilterChooserShortButtonLabel:(NSString *)localizedFilterChooserShortButtonLabel
localizedMatchingObjectsDescription:(NSString *)localizedMatchingObjectsDescription;
{
    OBPRECONDITION(identifier);
    OBPRECONDITION(imageName);
    OBPRECONDITION(predicate);
    OBPRECONDITION(localizedFilterChooserButtonLabel);
    OBPRECONDITION(localizedFilterChooserShortButtonLabel);
    OBPRECONDITION(localizedMatchingObjectsDescription);
    
    if (!(self = [super init]))
        return nil;
    
    _identifier = [identifier copy];
    _imageName = [imageName copy];
    _predicate = [predicate copy];
    _localizedFilterChooserButtonLabel = [localizedFilterChooserButtonLabel copy];
    _localizedFilterChooserShortButtonLabel = [localizedFilterChooserShortButtonLabel copy];
    _localizedMatchingObjectsDescription = [localizedMatchingObjectsDescription copy];
    
    return self;
}

@end
