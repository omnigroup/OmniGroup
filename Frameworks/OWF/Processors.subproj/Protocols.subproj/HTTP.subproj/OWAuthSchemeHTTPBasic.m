// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWAuthSchemeHTTPBasic.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation OWAuthSchemeHTTPBasic

- (NSString *)httpHeaderStringForProcessor:(OWHTTPProcessor *)aProcessor;
{
    NSMutableString *buffer = [[NSMutableString alloc] init];
    if (username)
        [buffer appendString:username];
    [buffer appendString:@":"];
    if (password)
        [buffer appendString:password];
        
    
#warning Encoding breakage is possible here
    // TODO: Find out what we're supposed to do if someone has kanji in their username or something
    
    NSData *bytes = [buffer dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:NO];
    if (bytes == nil) {
        [NSException raise:@"Can't Authorize" reason:NSLocalizedStringFromTableInBundle(@"Username or password contains characters which cannot be encoded", @"OWF", [OWAuthSchemeHTTPBasic bundle], @"authorization error")];
    }
    
    NSString *headerName;
    if (type == OWAuth_HTTP)
        headerName = @"Authorization";
    else if (type == OWAuth_HTTP_Proxy)
        headerName = @"Proxy-Authorization";
    else
        headerName = @"X-Bogus-Header"; // TODO
        
    return [NSString stringWithFormat:@"%@: Basic %@", headerName, [bytes base64EncodedStringWithOptions:0]];
}

- (BOOL)appliesToHTTPChallenge:(NSDictionary *)challenge
{
    // Correct scheme?
    if ([[challenge objectForKey:@"scheme"] caseInsensitiveCompare:@"basic"] != NSOrderedSame)
        return NO;
    
    // Correct realm?
    if (realm && [realm caseInsensitiveCompare:[challenge objectForKey:@"realm"]] != NSOrderedSame)
        return NO;
    
    return YES;
}
        
@end
