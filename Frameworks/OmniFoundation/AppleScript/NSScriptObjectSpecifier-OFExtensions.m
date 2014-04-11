// Copyright 2006-2008, 2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSScriptObjectSpecifier-OFExtensions.h>

#import <OmniBase/rcsid.h>
#import <Foundation/NSScriptExecutionContext.h>

RCS_ID("$Id$")

@interface NSScriptExecutionContext (PrivateAPI)
- (void)_resetErrorInfo;
- (void)_setErrorNumber:(NSUInteger)errorNumber;
@end

@implementation NSScriptObjectSpecifier (OFExtensions)
- (BOOL)specifiesSingleObject;
{
    // Subclass to return NO.
    return YES;
}
- (NSPropertySpecifier *)underlyingPropertySpecifier;
{
    return [self.containerSpecifier underlyingPropertySpecifier];
}

- (void)resetEvaluationError;
{
    /* If we do something (in OmniFocus) like "duplicate MyTask to after MyTask" then the positional specifier will look like
     
     <NSPositionalSpecifier: after <NSUniqueIDSpecifier: scriptTasks with an ID of "b-xFMQzYzTY" of orderedDocuments with an ID of "p3JirTMve4G">>
     
     but it won't be able to figure out the insertion container from this.  We could almost do this by resolving the object specifier and then checking if it has a 'container' property (in the OmniFocus case, the specifier doesn't give us the container since tasks ID them selves w.r.t. the document even if they are in a project or task group).  But we can't then figure out what the inverse relationship from the container to the object would be.
     */
    
    // RADAR 6227072: No public API to reset the error on an object specifier
    {
        // Reset the cached error number on the specifier; otherwise failed evaluation due to the position not being found (for example, since document->tasks isn't a real relationship) will make object resolution fail.
        // Note that if we just reset the evaluation error on the specifier, the next attempt to resolve will work, but the eventual error returned for the command will be the error first generated
        id ctx = [NSScriptExecutionContext sharedScriptExecutionContext];
        if ([ctx respondsToSelector:@selector(_resetErrorInfo)])
            [ctx performSelector:@selector(_resetErrorInfo)];
        if ([ctx respondsToSelector:@selector(_setErrorNumber:)]) {
            void (*imp)(id, SEL, NSUInteger) = (typeof(imp))objc_msgSend;
            imp(ctx, @selector(_setErrorNumber:), 0);
        }
        
        NSScriptObjectSpecifier *spec = self;
        while (spec) {
            [spec setEvaluationErrorNumber:NSNoSpecifierError];
            spec = [spec containerSpecifier];
        }
    }
}

@end

@interface NSPropertySpecifier (OFExtensions)
@end
@implementation NSPropertySpecifier (OFExtensions)

- (NSPropertySpecifier *)underlyingPropertySpecifier;
{
    return self;
}
@end

@interface NSRangeSpecifier (OFExtensions)
@end
@implementation NSRangeSpecifier (OFExtensions)
- (BOOL)specifiesSingleObject;
{
    return NO; // even if our range is a single index, we are asking for it as an array
}
- (NSPropertySpecifier *)underlyingPropertySpecifier;
{
    return [self.startSpecifier underlyingPropertySpecifier];
}
@end

@interface NSRelativeSpecifier (OFExtensions)
@end
@implementation NSRelativeSpecifier (OFExtensions)
- (BOOL)specifiesSingleObject;
{
    return [[self baseSpecifier] specifiesSingleObject];
}
- (NSPropertySpecifier *)underlyingPropertySpecifier;
{
    return [self.baseSpecifier underlyingPropertySpecifier];
}
@end

@interface NSWhoseSpecifier (OFExtensions)
@end
@implementation NSWhoseSpecifier (OFExtensions)
- (BOOL)specifiesSingleObject;
{
    NSWhoseSubelementIdentifier startSubelement = [self startSubelementIdentifier];
    NSWhoseSubelementIdentifier endSubelement = [self endSubelementIdentifier];
    
    // Requested a single item (start==index and end==index would probably be interpreted as a length 1 array)
    return ((startSubelement == NSIndexSubelement || startSubelement == NSMiddleSubelement || startSubelement == NSRandomSubelement) &&
            endSubelement == NSNoSubelement);
}
@end




