// Copyright 2006-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSComparisonPredicate.h>
#import <Foundation/NSCompoundPredicate.h>

#import <OmniFoundation/NSPredicate-OFExtensions.h>
#import <OmniFoundation/NSExpression-OFExtensions.h>

RCS_ID("$Id$");

@implementation NSPredicate (OFExtensions)

- (void)addReferencedKeys:(NSMutableSet *)keys;
{
    if ([self isEqual:[NSPredicate predicateWithValue:YES]] ||
        [self isEqual:[NSPredicate predicateWithValue:NO]])
        return;
    
    OBRequestConcreteImplementation(self, _cmd);
}

@end


@interface NSComparisonPredicate (OOExtensions)
- (void)addReferencedKeys:(NSMutableSet *)keys;
@end
@implementation NSComparisonPredicate (OOExtensions)
- (void)addReferencedKeys:(NSMutableSet *)keys;
{
    SEL sel = [self customSelector];
    if (sel == @selector(isKindOfClass:)) {
        // This should be 'SELF isKindOfClass: SOME_CLASS', but we don't have a good way of asserting this right now.
        return;
    }
    
    [[self leftExpression] addReferencedKeys:keys];
    [[self rightExpression] addReferencedKeys:keys];
}
@end

@interface NSCompoundPredicate (OOExtensions)
- (void)addReferencedKeys:(NSMutableSet *)keys;
@end
@implementation NSCompoundPredicate (OOExtensions)
- (void)addReferencedKeys:(NSMutableSet *)keys;
{
    [[self subpredicates] makeObjectsPerformSelector:_cmd withObject:keys];
}
@end


