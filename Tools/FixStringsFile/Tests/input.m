// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

RCS_ID("$Id$")

NSLocalizedStringFromTableInBundle(@"value", @"MultipleCommentsForOnePair", nil, @"comment a");
NSLocalizedStringFromTableInBundle(@"value", @"MultipleCommentsForOnePair", nil, @"comment c");
NSLocalizedStringFromTableInBundle(@"value", @"MultipleCommentsForOnePair", nil, @"comment b");

NSLocalizedStringFromTableInBundle(@"Format with \"%@\" quotes.", @"SmartQuotes", nil, @"should get curly quotes in the English localization");
NSLocalizedStringFromTableInBundle(@"Ellipsis...", @"Ellipsis", nil, @"three periods should get transformed to an ellipsis");

NSLocalizedStringFromTableInBundle(@"5 inches = 5\"", @"UnmatchedQuotes", nil, @"unmatched quotes shouldn't get curlied");

NSLocalizedStringFromTableInBundle(@"Level %[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]@ Rows", @"MultiplePairsForOneComment", nil, @"genstrings can report multiple key/value pairs for the cross-product style source strings");
