

NSLocalizedStringFromTableInBundle(@"value", @"MultipleCommentsForOnePair", nil, @"comment a");
NSLocalizedStringFromTableInBundle(@"value", @"MultipleCommentsForOnePair", nil, @"comment c");
NSLocalizedStringFromTableInBundle(@"value", @"MultipleCommentsForOnePair", nil, @"comment b");

NSLocalizedStringFromTableInBundle(@"Format with \"%@\" quotes.", @"SmartQuotes", nil, @"should get curly quotes in the English localization");
NSLocalizedStringFromTableInBundle(@"Ellipsis...", @"Ellipsis", nil, @"three periods should get transformed to an ellipsis");

NSLocalizedStringFromTableInBundle(@"5 inches = 5\"", @"UnmatchedQuotes", nil, @"unmatched quotes shouldn't get curlied");

NSLocalizedStringFromTableInBundle(@"Level %[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]@ rows", @"MultiplePairsForOneComment", nil, @"genstrings can report multiple key/value pairs for the cross-product style source strings");
