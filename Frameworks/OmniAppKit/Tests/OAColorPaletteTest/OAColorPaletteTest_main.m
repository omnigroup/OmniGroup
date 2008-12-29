// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniAppKit/OmniAppKit.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Tests/OAColorPaletteTest/OAColorPaletteTest_main.m 68913 2005-10-03 19:36:19Z kc $")

void TestOAColorPalette(void);
void testColor(NSString *colorString);

int main (int argc, const char *argv[])
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    TestOAColorPalette();

    [pool release];
    return 0;
}

void TestOAColorPalette(void)
{
    testColor(@"");
    testColor(@"#");
    testColor(@"#f00");
    testColor(@"#080");
    testColor(@"001");
    testColor(@"0010");
    testColor(@"000000");
    testColor(@"1Offff");
    testColor(@"1OOOOO");
    testColor(@"fff8007ff");
    testColor(@"001002003");
    testColor(@"red");
    testColor(@"green");
    testColor(@"#blue");
    testColor(@"bogus");
    testColor(@"#bogus");
}

void testColor(NSString *colorString)
{
    NSLog(@"\"%@\" -> %@", colorString, [OAColorPalette colorForString:colorString gamma:1.0]);
}
