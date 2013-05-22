// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSURL-OFExtensions.h>

#import <OmniBase/OBUtilities.h>

RCS_ID("$Id$")

OB_REQUIRE_ARC

#if defined(DEBUG_bungi)
// Patch -[NSURL isEqual:] and -hash to asssert. Don't use these as dictionary keys due to their issues with comparison (standardized paths for /var/private, trailing slash, case comparison bugs with hex-encoded octets).
static BOOL (*original_NSURL_isEqual)(NSURL *self, SEL _cmd, id otherObject);
static NSUInteger (*original_NSURL_hash)(NSURL *self, SEL _cmd);

static BOOL replacement_NSURL_isEqual(NSURL *self, SEL _cmd, id otherObject)
{
    if ([self isFileURL]) {
        // NSFileManager calls -isEqual: on the two URLs given to -writeToURL:options:originalContentsURL:error:, so we ignore file URLs.
    } else if ([[self absoluteString] length] == 0) {
        // OSURLStyleAttribute's default value
        
    } else {
        OBASSERT_NOT_REACHED("Don't call -[NSURL isEqual:]");
    }
    
    return original_NSURL_isEqual(self, _cmd, otherObject);
}

static NSUInteger replacement_NSURL_hash(NSURL *self, SEL _cmd)
{
    OBASSERT_NOT_REACHED("Don't call -[NSURL hash]");
    return original_NSURL_hash(self, _cmd);
}

static void patchURL(void) __attribute__((constructor));
static void patchURL(void)
{
    Class cls = [NSURL class];
    original_NSURL_isEqual = (typeof(original_NSURL_isEqual))OBReplaceMethodImplementation(cls, @selector(isEqual:), (IMP)replacement_NSURL_isEqual);
    original_NSURL_hash = (typeof(original_NSURL_hash))OBReplaceMethodImplementation(cls, @selector(hash), (IMP)replacement_NSURL_hash);
}


#endif


NSRange OFURLRangeOfPath(NSString *rfc1808URL)
{
    if (!rfc1808URL) {
        return (NSRange){NSNotFound, 0};
    }
    
    NSRange colon = [rfc1808URL rangeOfString:@":"];
    if (!colon.length) {
        return (NSRange){NSNotFound, 0};
    }
    
    NSUInteger len = [rfc1808URL length];
#define Suffix(pos) (NSRange){(pos), len - (pos)}
    
    // The fragment identifier is significant anywhere after the colon (and forbidden before the colon, but whatever)
    NSRange terminator = [rfc1808URL rangeOfString:@"#" options:0 range:Suffix(NSMaxRange(colon))];
    if (terminator.length)
        len = terminator.location;
    
    // According to RFC1808, the ? and ; characters do not have special meaning within the host specifier.
    // But the host specifier is an optional part (again, according to the RFC), so we need to only optionally skip it.
    NSRange pathRange;
    NSRange slashes = [rfc1808URL rangeOfString:@"//" options:NSAnchoredSearch range:Suffix(NSMaxRange(colon))];
    if (slashes.length) {
        NSRange firstPathSlash = [rfc1808URL rangeOfString:@"/" options:0 range:Suffix(NSMaxRange(slashes))];
        if (!firstPathSlash.length) {
            // A URL of the form foo://bar.com
            return (NSRange){ len, 0 };
        } else {
            pathRange.location = firstPathSlash.location;
        }
    } else {
        // The first character after the colon may or may not be a slash; RFC1808 allows relative paths there.
        pathRange.location = NSMaxRange(colon);
    }
    
    pathRange.length = len - pathRange.location;
    
    // Strip any query
    terminator = [rfc1808URL rangeOfString:@"?" options:0 range:pathRange];
    if (terminator.length)
        pathRange.length = terminator.location - pathRange.location;
    
    // Strip any parameter-string
    [rfc1808URL rangeOfString:@";" options:0 range:pathRange];
    if (terminator.length)
        pathRange.length = terminator.location - pathRange.location;
    
    return pathRange;
}

NSURL *OFURLWithTrailingSlash(NSURL *baseURL)
{
    if (baseURL == nil)
        return nil;
    
    if ([[baseURL path] hasSuffix:@"/"])
        return baseURL;
    
    NSString *baseURLString = [baseURL absoluteString];
    NSRange pathRange = OFURLRangeOfPath(baseURLString);
    
    if (pathRange.length && [baseURLString rangeOfString:@"/" options:NSAnchoredSearch|NSBackwardsSearch range:pathRange].length > 0)
        return baseURL;
    
    NSMutableString *newString = [baseURLString mutableCopy];
    [newString insertString:@"/" atIndex:NSMaxRange(pathRange)];
    NSURL *newURL = [NSURL URLWithString:newString];
    
    return newURL;
}

BOOL OFURLEqualsURL(NSURL *URL1, NSURL *URL2)
{
    if (URL1 == URL2)
        return YES;
    if (!URL1 || !URL2)
        return NO;
    
    URL1 = [URL1 absoluteURL];
    URL2 = [URL2 absoluteURL];
    
    // This assumes that -path keeps the trailing slash and that we want slash differences to be significant (might want to change that).
    if (OFNOTEQUAL([URL1 path], [URL2 path]))
        return NO;
    
    // Some other bits should maybe be URL-decoded before comparison too. Also, we should maybe just assert that all the goofy stuff is nil for OFS-used URLs.
    return
    OFISEQUAL(URL1.scheme, URL2.scheme) &&
    OFISEQUAL(URL1.host, URL2.host) &&
    OFISEQUAL(URL1.port, URL2.port) &&
    OFISEQUAL(URL1.user, URL2.user) &&
    OFISEQUAL(URL1.password, URL2.password) &&
    OFISEQUAL(URL1.fragment, URL2.fragment) &&
    OFISEQUAL(URL1.parameterString, URL2.parameterString) &&
    OFISEQUAL(URL1.query, URL2.query);
}

BOOL OFURLEqualToURLIgnoringTrailingSlash(NSURL *URL1, NSURL *URL2)
{
    if (OFURLEqualsURL(URL1, URL2))
        return YES;
    return OFURLEqualsURL(OFURLWithTrailingSlash(URL1), OFURLWithTrailingSlash(URL2));
}

