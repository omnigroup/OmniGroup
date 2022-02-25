// Copyright 2006-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSExpression-OFExtensions.h>

RCS_ID("$Id$");

@implementation NSExpression (OFExtensions)

- (void)addReferencedKeys:(NSMutableSet *)keys;
{
    switch ([self expressionType]) {
        case NSConstantValueExpressionType:
            break;
        case NSEvaluatedObjectExpressionType:
            break;
        case NSKeyPathExpressionType:
            [keys addObject:[self keyPath]];
            break;
        case NSVariableExpressionType:
        case NSBlockExpressionType:
        case NSFunctionExpressionType:
            // Ignore variables; the caller will need to deal with those
            break;
        default:
            OBRequestConcreteImplementation(self, _cmd);
            break;
    }
}

@end
