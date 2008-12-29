// Copyright 2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSComparisonPredicate-OFExtensions.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSComparisonPredicate-OFExtensions.m 98770 2008-03-17 22:25:33Z kc $");

#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4

@implementation NSComparisonPredicate (OFExtensions)

+ (NSPredicate *)isKindOfClassPredicate:(Class)cls;
{
    NSExpression *classExpression = [NSExpression expressionForConstantValue:cls];
    NSExpression *inputObject = [NSExpression expressionForEvaluatedObject];
    return [NSComparisonPredicate predicateWithLeftExpression:inputObject rightExpression:classExpression customSelector:@selector(isKindOfClass:)];
}

+ (NSPredicate *)conformsToProtocolPredicate:(Protocol *)protocol;
{
    NSExpression *protocolExpression = [NSExpression expressionForConstantValue:protocol];
    NSExpression *inputObject = [NSExpression expressionForEvaluatedObject];
    return [NSComparisonPredicate predicateWithLeftExpression:inputObject rightExpression:protocolExpression customSelector:@selector(conformsToProtocol:)];
}

@end

#endif
