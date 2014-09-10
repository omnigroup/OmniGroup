// Copyright 2003-2005, 2014 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAddress.h>
#import <OWF/OWURL.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <XCTest/XCTest.h>

RCS_ID("$Id$");

@interface OWAddressTests : XCTestCase
{
}
@end

@interface OWURLTests : XCTestCase
{
}
@end

@implementation OWAddressTests

// Test cases

- (void)testDirtyStringParsing
{
#define DirtyString(in, out) XCTAssertEqualObjects([[OWAddress addressForDirtyString:in] addressString], out)

    DirtyString(@"omnigroup", @"<URL:http://www.omnigroup.com/>");
    DirtyString(@"omnigroup/products", @"<URL:http://www.omnigroup.com/products>");
    DirtyString(@"/System", @"<URL:file:///System>");
    DirtyString(@"www.omnigroup.com:80", @"<URL:http://www.omnigroup.com:80/>");

    DirtyString(@"     http://www.foo.bar.com/this/that#another\n  ", @"<URL:http://www.foo.bar.com/this/that#another>");
    DirtyString(@"   http://www.foo.bar.com/this/that/another/\n      long/url/of/doom\n", @"<URL:http://www.foo.bar.com/this/that/another/long/url/of/doom>");
    
}

@end

@implementation OWURLTests


static inline void testURL(OWURLTests *self, NSString *inputString, NSString *expectedResult)
{
    XCTAssertEqualObjects([[OWURL urlFromDirtyString:inputString] compositeString], expectedResult);
}

static inline void testSimpleURL(OWURLTests *self, NSString *inputString)
{
    testURL(self, inputString, inputString);
}

static inline void testCanonicalURL(OWURLTests *self, NSString *inputString)
{
    testURL(self, inputString, [[inputString stringByRemovingPrefix:@"<URL:"] stringByRemovingSuffix:@">"]);
}

static inline void testRelativeURL(NSString *urlString)
{
    static OWURL *baseURL = nil;

    if (!baseURL) {
        baseURL = [OWURL urlFromDirtyString:@"<URL:http://a/b/c/d;p?q#f>"];
        NSLog(@"Base: %@", [baseURL shortDescription]);
    }

    NSLog(@"%@ = %@", [urlString stringByPaddingToLength:13], [[baseURL urlFromRelativeString:urlString] shortDescription]);
}

static inline void testDomain(NSString *urlString)
{
    NSLog(@"'%@' is in the '%@' domain", urlString, [[OWURL urlFromDirtyString:urlString] domain]);
}


- (void)testDomains
{
    testDomain(@"http://omnigroup.com:8080");
    // Note: This next test executes before com is registered as a short top-level domain, so it returns www.omnigroup.com.
    testDomain(@"http://www.omnigroup.com");
    testDomain(@"http://omnigroup.co.uk");
    testDomain(@"http://www.omnigroup.co.uk");
}

- (void)testParsing
{
    testSimpleURL(self, @"http://www.omnigroup.com/Test/path.html");
    testURL(self, @"file:/LocalLibrary/Web/", @"file:///LocalLibrary/Web/");
    testSimpleURL(self, @"http://www.omnigroup.com/blegga.cgi?blah");
    testCanonicalURL(self, @"<URL:ftp://ds.internic.net/rfc/rfc1436.txt;type=a>");
    testCanonicalURL(self, @"<URL:ftp://info.cern.ch/pub/www/doc;type=d>");
    testURL(self, @"<URL:ftp://info.cern.ch/pub/www/doc;\n      type=d>", @"ftp://info.cern.ch/pub/www/doc;type=d");
    testURL(self, @"<URL:ftp://ds.in\n      ternic.net/rfc>", @"ftp://ds.in\n      ternic.net/rfc");
    testURL(self, @"<URL:http://ds.internic.\n      net/instructions/overview.html#WARNING>", @"http://ds.internic.net/instructions/overview.html#WARNING");
    testURL(self, @"index.html", nil);
    testURL(self, @"../index.html", nil);
    testSimpleURL(self, @"http://www.nick.com/flash_inits/ainit_container.swf?movie0=/flash_inits/multimedia/logo_atom.swf&movie0_url=#&clicked0=#&movie1=/flash_inits/multimedia/kca2004.swf&movie1_url=/all_nick/specials/kca_2004/&clicked1=/flash_inits/multimedia/click_all_nick.swf&movie2=/flash_inits/multimedia/e_collect2004_fop.swf&movie2_url=/home/mynick/&clicked2=/flash_inits/multimedia/click_games.swf&movie3=/flash_inits/multimedia/sb_bowling.swf&movie3_url=/games/game.jhtml?game-name=sb_bowling&clicked3=/flash_inits/multimedia/click_games.swf&movie4=/flash_inits/multimedia/fop_superwishgame.swf&movie4_url=/games/data/fairlyoddparents/fop_hero/playGame.jhtml&clicked4=/flash_inits/multimedia/click_games.swf&movie5=/flash_inits/multimedia/amanda_games.swf&movie5_url=/amandaplease/archive/index.jhtml&clicked5=/flash_inits/multimedia/click_all_nick.swf&path=&section=home&redval=205&greenval=255&blueval=0&isLoaded=1&");
}

- (void)testRelativeURLs
{
    testRelativeURL(@"g:h");
    testRelativeURL(@"g");
    testRelativeURL(@"./g");
    testRelativeURL(@"g/");
    testRelativeURL(@"/g");
    testRelativeURL(@"//g");
    testRelativeURL(@"?y");
    testRelativeURL(@"g?y");
    testRelativeURL(@"g?y/./x");
    testRelativeURL(@"#s");
    testRelativeURL(@"g#s");
    testRelativeURL(@"g#s/./x");
    testRelativeURL(@"g?y#s");
    testRelativeURL(@";x");
    testRelativeURL(@"g;x");
    testRelativeURL(@"g;x?y#s");
    testRelativeURL(@".");
    testRelativeURL(@"./");
    testRelativeURL(@"..");
    testRelativeURL(@"../");
    testRelativeURL(@"../g");
    testRelativeURL(@"../..");
    testRelativeURL(@"../../");
    testRelativeURL(@"../../g");

    testRelativeURL(@"");
    testRelativeURL(@"../../../g");
    testRelativeURL(@"../../../../g");
    testRelativeURL(@"/./g");
    testRelativeURL(@"/../g");
    testRelativeURL(@"g.");
    testRelativeURL(@".g");
    testRelativeURL(@"g..");
    testRelativeURL(@"..g");
    testRelativeURL(@"./../g");
    testRelativeURL(@"./g/.");
    testRelativeURL(@"g/./h");
    testRelativeURL(@"g/../h");
    testRelativeURL(@"http:g");
    testRelativeURL(@"http:");
}

@end

