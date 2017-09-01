OmniGroup
===========

Checking out the source
-----------------------

    git clone git://github.com/omnigroup/OmniGroup
    git submodule update --init

Xcode
-------------------

- We currently use Xcode 9 beta 6 for all platforms. You'll probably have the best results if you do too.
- Add the projects you want to your workspace.
- Take a look in the Workspaces directory for a sample workspace for the TextEditor iPad example app.

Supported Targets
----------------------

- We require iOS 11 and Mac OS X 10.11.

Configuring the Source
----------------------

We place our project-wide configuration options in xcconfig files, under `OmniGroup/Configurations`. The naming scheme of the files is fairly straightforward, hopefully. Each project has `Omni-Global-{Debug,Release,...}.xcconfig` as the basis for the corresponding configuration. Each Mac target has `Omni-{Bundle,Application,Tool,...}-{Debug,Release,...}.xcconfig` and each iOS target has `Touch-{Application,Library}-{Debug,Release,...}.xcconfig`. Each of these end point configurations when `#include`s 'superclass' configurations (with "Common" in the name).

 
Building
--------

The Workspaces directory contains a couple sample workspace that can be built from Xcode.

Enjoy!
