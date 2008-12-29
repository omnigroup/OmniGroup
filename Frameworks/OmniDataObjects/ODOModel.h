// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOModel.h 104583 2008-09-06 21:23:18Z kc $

#import <OmniFoundation/OFObject.h>

@class NSDictionary;
@class ODOEntity;

extern NSString * const ODOModelRootElementName;
extern NSString * const ODOModelNamespaceURLString;

@interface ODOModel : OFObject
{
@private
    NSString *_path;
    NSDictionary *_entitiesByName;
}

+ (NSString *)internName:(NSString *)name;

- (id)initWithContentsOfFile:(NSString *)path error:(NSError **)outError;
- (NSDictionary *)entitiesByName;

- (ODOEntity *)entityNamed:(NSString *)name;

@end
