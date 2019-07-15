// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// String constants that can be placed in a schema dictionary

#define OFDocEncryptionExposeName     @"Name"          // Value is the filename which this member should be exposed as in the encrypted wrapper
#define OFDocEncryptionFileOptions    @"Options"       // Value is a boxed OFCMSOptions
#define OFDocEncryptionChildren       @"Children"      // Value is a dictionary mapping names to schema dictionaries

// Metadata keys supplied by our Spotlight helper methods.
// Each importer will need to declare these itself.
#define OFMDItemEncryptionRecipientCount         @"com_omnigroup_DocumentEncryption_recipientCount"
#define OFMDItemEncryptionPassphraseIdentifier   @"com_omnigroup_DocumentEncryption_passphraseIdentifier"
