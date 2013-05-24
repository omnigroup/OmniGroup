// Copyright 2012-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
    
#import <OmniAppKit/NSNib-OAExtensions.h>

RCS_ID("$Id$");

// <bug:///89033> (Update/remove NSNib(OAExtensions) to us non-deprecated API)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation NSNib (OAExtensions)

- (NSArray *)instantiateNibWithOwner:(id)owner options:(NSDictionary *)options;
{
    // The options parameter is currently unused.
    OBPRECONDITION(!options || [options count] == 0);

    // ...but when we start using it, we definitely want to ensure the user isn't trying to use -instantiateNibWithExternalNameTable: semantics.
    OBPRECONDITION([options objectForKey:NSNibOwner] == nil);
    OBPRECONDITION([options objectForKey:NSNibTopLevelObjects] == nil);
    
    NSArray *topLevelObjects = nil;
    if (!([self instantiateNibWithOwner:owner topLevelObjects:&topLevelObjects])) {
        NSString *reason = [NSString stringWithFormat:@"Unable to load nib %@", OBShortObjectDescription(self)];
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
    }
    
    // The top level objects all have an "extra" reference associated with them.
    // Clear that extra reference here. Our documented policy is the same as UINibLoading-the caller should retain the returned array (or the objects individually, through strong IBOutlets, to prevent the top level objects from being released prematurely.
    //
    // We do this with CFRelease so that we won't have to come back and modify this code for ARC compatibility in the future.
    
    [topLevelObjects enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop) {
        CFRelease(object);
    }];

    return topLevelObjects;
}

@end

#pragma clang diagnostic pop
